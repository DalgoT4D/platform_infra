# Staging RDS: databases and users

A new RDS has only the master user `postgres`. Create one database and one user per app, all as `postgres`.

| App | Database | User |
|---|---|---|
| Airbyte | `airbyte` | `airbyte_user` (+ `CREATEDB`: Airbyte's Temporal creates `temporal` and `temporal_visibility` itself) |
| Prefect server | `prefect` | `prefect_user` |
| Dalgo backend | `dalgo` | `dalgo_user` |

Generate each password with `openssl rand -base64 24 | tr -d '/@"+='` and save it in the vault first.

## 1. Connect as `postgres`

The RDS is private: connect from the staging EC2.

```bash
sudo apt-get install -y postgresql-client
psql "host=<rds-endpoint> user=postgres dbname=postgres sslmode=require"   # master password from the vault
```

`<rds-endpoint>`: `terraform output endpoint` in this folder.

## 2. Create users, databases, permissions

Paste into `psql`:

```sql
-- Airbyte
CREATE USER airbyte_user PASSWORD '<airbyte_password>' CREATEDB;
CREATE DATABASE airbyte;
REVOKE ALL ON DATABASE airbyte FROM PUBLIC;
GRANT ALL PRIVILEGES ON DATABASE airbyte TO airbyte_user;
\c airbyte
GRANT ALL ON SCHEMA public TO airbyte_user;
\c postgres

-- Prefect
CREATE USER prefect_user PASSWORD '<prefect_password>';
CREATE DATABASE prefect;
REVOKE ALL ON DATABASE prefect FROM PUBLIC;
GRANT ALL PRIVILEGES ON DATABASE prefect TO prefect_user;
\c prefect
GRANT ALL ON SCHEMA public TO prefect_user;
\c postgres

-- Dalgo
CREATE USER dalgo_user PASSWORD '<dalgo_password>';
CREATE DATABASE dalgo;
REVOKE ALL ON DATABASE dalgo FROM PUBLIC;
GRANT ALL PRIVILEGES ON DATABASE dalgo TO dalgo_user;
\c dalgo
GRANT ALL ON SCHEMA public TO dalgo_user;
\c postgres
```

What each line does:

| Command | Effect |
|---|---|
| `CREATE DATABASE` | database owned by `postgres` |
| `REVOKE ALL ON DATABASE … FROM PUBLIC` | removes Postgres's default "every user may connect" (`PUBLIC` = all users, not the schema) |
| `GRANT ALL PRIVILEGES ON DATABASE … TO <user>` | the app user may connect and create schemas |
| `GRANT ALL ON SCHEMA public TO <user>` | the app user may create tables, views etc. in the `public` schema (Postgres 15+ doesn't allow this by default) |

Each app user owns, and has full rights on, everything it creates. It can't connect to the other apps' databases.

## 3. Check

```sql
\du    -- users
\l     -- databases
```

```bash
psql "host=<rds-endpoint> user=dalgo_user dbname=dalgo   sslmode=require" -c "create table t(i int); drop table t;"   # works
psql "host=<rds-endpoint> user=dalgo_user dbname=airbyte sslmode=require" -c "select 1;"                            # denied
```

## 4. Put the credentials in the apps

| App | Where |
|---|---|
| Airbyte | `airbyte/helm/airbyte-config-secrets.yaml`: `database-user`, `database-password`, `DATABASE_USER`, `DATABASE_PASSWORD`; `database: airbyte` in `values1.8.3.yaml` |
| Prefect server | `PREFECT_API_DATABASE_CONNECTION_URL=postgresql+asyncpg://prefect_user:<prefect_password>@<rds-endpoint>:5432/prefect` |
| Dalgo backend | `.env`: `DBHOST=<rds-endpoint>`, `DBNAME=dalgo`, `DBUSER=dalgo_user`, `DBPASSWORD` |

## Change a password

```sql
ALTER USER <user> PASSWORD '<new_password>';
```

Then update the vault and the app config, and restart the app.
