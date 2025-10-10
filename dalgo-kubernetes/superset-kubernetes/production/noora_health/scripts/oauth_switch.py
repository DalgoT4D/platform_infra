from datetime import datetime
import psycopg2
import os
import sys

from dotenv import load_dotenv

class OauthSwitch():

    def __init__(self, creds: dict, prefix: str = "oldnoora_", dry_run: bool = True):
        self.connection = psycopg2.connect(
            user=creds.get("user"),
            password=creds.get("password"),
            host=creds.get("host"),
            port=creds.get("port"),
            database=creds.get("database"),
        )
        self.prefix = prefix
        self.dry_run = dry_run

    def prefix_users_email(self):
        """Prefix users email with self.prefix"""

        cursor = self.connection.cursor()
        if self.dry_run:
            # In dry run mode, just count and print what would be updated
            cursor.execute(
            """
                SELECT COUNT(*) 
                FROM ab_user 
                WHERE email NOT LIKE %s AND username NOT LIKE %s;
            """, (f"{self.prefix}%", "google%"))
            
            count = cursor.fetchone()[0]
            print(f"[DRY RUN] Would update {count} users with prefix '{self.prefix}'")
            
            # Optionally show some examples
            cursor.execute(
            """
                SELECT id, email, username 
                FROM ab_user 
                WHERE email NOT LIKE %s AND username NOT LIKE %s
                LIMIT 5;
            """, (f"{self.prefix}%", "google%"))
            
            examples = cursor.fetchall()
            print("[DRY RUN] Examples of emails that would be updated:")
            for user_id, email, username in examples:
                print(f"  {user_id}: {email} -> {self.prefix}{email} (user: {username})")
                
            if count > 5:
                print(f"  ... and {count - 5} more")

        else:
            # Actually run the update
            cursor.execute(
            """
                UPDATE ab_user 
                SET email = CONCAT(%s, email)
                WHERE email NOT LIKE %s AND username NOT LIKE %s;
            """, (self.prefix, f"{self.prefix}%", "google%"))
            
            affected_rows = cursor.rowcount
            self.connection.commit()
            print(f"Updated {affected_rows} users with prefix '{self.prefix}'")

    def swap_oauth_basic_user_records(self, email: str) -> bool:
        """
        Swap records of basic auth user and oauth user based on email
        The new record of the user or the oauth will always have the id greater than the old one
        We need 
        1. to check whether the new one is invalidated with details of old prefixed user and old one is a google oauth user
        2. if 1 has not happened, then we need to swap details of new one (with greater id) with old one (with smaller id)
        3. if 1 has happened, then we are good swap has already happened
        """

        # remove the prefix if it exists
        if email.startswith(self.prefix):
            email = email.replace(self.prefix, "", 1)

        cursor = self.connection.cursor()
        cursor.execute("SELECT * FROM ab_user WHERE email LIKE %s;", (f"%{email}%",))
        rows = cursor.fetchall()

        # convert to list of dicts for easier handling
        rows_dict = []
        column_names = [desc[0] for desc in cursor.description]
        for row in rows:
            rows_dict.append(dict(zip(column_names, row)))


        if not rows:
            print("No record found for email - ", email, "\n")
            return False
        
        if len(rows) == 1:
            # get the email and print it
            curr_email = rows_dict[0]["email"]
            print("Only 1 record found for email - ", curr_email, "\n")
            return False

        if len(rows) > 2:
            emails = [row["email"] for row in rows_dict]
            print("More than 2 emails found - ", emails, "\n")
            return False

        # we only proceed when we have exactly 2 records
        # sort by id in ascending order
        rows_dict = sorted(rows_dict, key=lambda x: x["id"])

        old_record = rows_dict[0]
        new_record = rows_dict[1]

        if old_record["username"].startswith("google"):
            print("Exiting: The record is already a Google OAuth record. Please check again\n")
            return True
       

        if new_record["email"].startswith(self.prefix):
            print(f"Exiting: The email already has prefix {self.prefix}. Please check again. Looks like the script has already ran\n")
            return True
        
        cols_to_copy = [
            "username",
            "password",
            "email",
        ]
        
        try:

            # start a transaction
            cursor.execute("BEGIN;")

            # since there is unique constraint on email & username
            # set them to some temp values for now
            # we will revert everything if it fails

            update_old_query = """
                UPDATE ab_user
                SET email = %s, username = %s
                WHERE id = %s;
            """
            cursor.execute(
                update_old_query,
                (
                    f"{old_record['email']}_temp",
                    f"{old_record['username']}_temp",
                    old_record["id"],
                ),
            )

            update_new_query = """
                UPDATE ab_user
                SET email = %s, username = %s
                WHERE id = %s;
            """
            cursor.execute(
                update_new_query,
                (
                    f"{new_record['email']}_temp",
                    f"{new_record['username']}_temp",
                    new_record["id"],
                ),
            )

            # now copy from one to another
            set_clause = ", ".join([f"{col} = %s" for col in cols_to_copy])

            update_old_query = f"""
                UPDATE ab_user
                SET {set_clause}
                WHERE id = %s;
            """
            cursor.execute(
                update_old_query,
                (*[new_record[col] for col in cols_to_copy], old_record["id"]),
            )

            update_new_query = f"""
                UPDATE ab_user
                SET {set_clause}
                WHERE id = %s;
            """
            cursor.execute(
                update_new_query,
                (*[old_record[col] for col in cols_to_copy], new_record["id"]),
            )

            self.connection.commit()
            print("Records updated successfully.\n")

        except (Exception, psycopg2.Error) as error:
            print("Error while updating records", error)
            self.connection.rollback()
            return False


    def oauth_migration_status(self) -> list[dict]:
        """
        Check the migration status of users from basic auth to OAuth
        1. Check how many users have been prefixed. This is the base/denominator for migration
        2. Off the users in 1) how many have a corresponding oauth user (with same email without prefix)
        3. How many of the users in 2) have been swapped successfully i.e. id of the google user is less than the id of the prefixed user
        4. How many users are left to be swapped

        Returns list of email ids of users that are not swapped yet
        """

        # 1. find total prefixed users
        cursor = self.connection.cursor()
        cursor.execute(
            """
                SELECT * 
                FROM ab_user 
                WHERE email LIKE %s;
            """, (f"{self.prefix}%",))
        rows = cursor.fetchall()

        if not rows:
            print("No users found for migration.")
            return []

        total_prefixed_users = len(rows)

        # convert to list of dicts for easier handling
        rows_dict = []
        column_names = [desc[0] for desc in cursor.description]
        for row in rows:
            rows_dict.append(dict(zip(column_names, row)))

        # 2. find how many of these have a corresponding oauth user (i.e. signed in)
        users_signed_in = []
        users_not_signed_in = []
        for row in rows_dict:
            email_without_prefix = row["email"].replace(self.prefix, "", 1)
            try:
                cursor.execute(
                    """
                        SELECT * 
                        FROM ab_user 
                        WHERE email = %s AND username LIKE %s;
                    """, (email_without_prefix, "google%")
                )
                oauth_row = cursor.fetchone()
                if oauth_row:
                    users_signed_in.append(row)
                else:
                    users_not_signed_in.append(row)
            except Exception as e:
                print(f"Error checking OAuth user for email {email_without_prefix}: {e}")
                continue

        # 3. find how many of the users in 2) have been swapped successfully
        oauth_users_not_swapped_list = []
        oauth_users_swapped_list = []
        for row in rows_dict:
            email_without_prefix = row["email"].replace(self.prefix, "", 1)
            cursor.execute(
                """
                    SELECT * 
                    FROM ab_user 
                    WHERE email = %s AND username LIKE %s;
                """, (email_without_prefix, "google%"))
            oauth_row = cursor.fetchone()
            if oauth_row:
                oauth_dict = dict(zip(column_names, oauth_row))
                if oauth_dict["id"] < row["id"]:
                    oauth_users_swapped_list.append(row)
                else:
                    oauth_users_not_swapped_list.append(row)

        print("""
Total users to be migrated (prefixed): %s
Total users (google) signed in: %s
Total users not (google) signed in: %s
Total users migrated successfully: %s
Total users signed in but not migrated: %s
        """ % (
                total_prefixed_users, 
                len(users_signed_in), 
                len(users_not_signed_in), 
                len(oauth_users_swapped_list),
                len(oauth_users_not_swapped_list)
            ) 
        )

        return [user['email'] for user in oauth_users_not_swapped_list]

    def close(self):
        if self.connection:
            self.connection.close()
            print("PostgreSQL connection is closed")

if __name__ == "__main__":
    load_dotenv()

    oauth_switch = OauthSwitch(
        creds={
            "user": os.getenv("DB_USER"),
            "password": os.getenv("DB_PASSWORD"),
            "host": os.getenv("DB_HOST"),
            "port": os.getenv("DB_PORT"),
            "database": os.getenv("DB_NAME"),
        },
        prefix="oldnoora_",
        dry_run=False
    )
    
    # THIS IS STEP IS DONE: ONLY TO BE RUN ONCE AT THE START OF THE MIGRATION
    # oauth_switch.prefix_users_email()

    # print the start time stamp
    print(f"================= Start - {datetime.now().strftime('%d %b %I:%M %p')} ============\n")

    not_swapped_users: list[str] = oauth_switch.oauth_migration_status()

    for email in not_swapped_users:
        print(f"Swapping user with email: {email}")
        oauth_switch.swap_oauth_basic_user_records(email)

    oauth_switch.oauth_migration_status()

    print(f"================== End ===========================================================\n")

    oauth_switch.close()