Procedure to use terraform scripts for “superset” deployment.


Script  Overview : 


It consists of two sections, one making applications available on the given remote application server and second creating resources on aws infrastructure or configure aws components in such a way that http traffic from client are redirected via load balancer to application running on ec2 instance.


First part
 


1. Pulling the latest “docker-superset” repo from github viz.


https://github.com/DalgoT4D/docker-superset.git


2. Generate_make_client                                    ⇐  take input from terraform.tfvars 
3. Updates “superset.env”                                 ⇐  take input from terraform.tfvars
4. Ship entire repo to remote machine with docker-compose.yml and superset.env.
5. Execute build.sh                                             <= build container onto remote machine.
6. docker compose                                             <= launch application
7. start-superset.sh                                             <= create admin user and db migration


Second Part


1. Adding listener rule to existing HTTP 443 port of given load balancer.
2. Adding ingress inbound rule onto existing security group of Application server.




Terraform.tfvars




# Below parameters are needed for script execution


Location of script directory, terraform will be execute from here
AUTOROOT_DIR        = "/home/XXXX/YYYY"


Remote user login on application server ( usually it's “ubuntu” )
REMOTE_USER         = "ubuntu"


SSH Key on local machine
SSH_KEY             = "/home/XXX/.ssh/id_rsa.pem"


Local directory where repo is copied,will be deleted at every execution
LOCAL_CLONE_DIR     = "/home/XXX/YYY/superset-repo"


Superserset, don’t want to hardcode, incase of future changes
SUPERSET_MIDDLE_DIR = "gensuperset/make-client"


Remote machine directory, where repo is copied
So superset.env, will be available in /home/ubuntu/gensuperset/make-client/testngo1/superset.env


REMOTE_CLONE_DIR    = "/home/ubuntu"


RDS name used in your aws environment
rdsname             = "rail-db-1"


# End




# Below parameters are for Generate make client


CLIENT_NAME        = "testngo1"
PROJECT_OR_ENV     = "prod"
BASE_IMAGE         = "tech4dev/superset:4.1.1"
SUPERSET_VERSION   = "4"
OUTPUT_IMAGE_TAG   = "1.1"
CONTAINER_PORT     = "9990"
CELERY_FLOWER_PORT = "5555"
ARCH_TYPE          = "linux/amd64"
OUTPUT_DIR         = "testngo1"


# End


# Below Parameters are needed for superset.env


SUPERSET_ADMIN_USERNAME = "YYY"                   ⇐ Client GUI login name
SUPERSET_ADMIN_PASSWORD = "XXXX"                  ⇐ Client GUI password
SUPERSET_ADMIN_EMAIL    = "admin@ngo.org"         ⇐ Client mail
POSTGRES_USER           = "XXXX"                  ⇐ Postgres login
POSTGRES_PASSWORD       = "YYYYY"                 ⇐ Postgres password
APP_DB_USER             = "XXXXX_testngo1"        ⇐ Client user for app
APP_DB_PASS             = "testngo1"              ⇐ Client passwd for app
APP_DB_NAME             = "XXXXX_testngo1"        ⇐ Client database
ENABLE_OAUTH            = ""                      ⇐ Empty as of now


# End


# Below Parameters required for aws resource creation


alb_name      = "rails-alb-1  "             ⇐ Load Balancer name
cur_vpc       = "vpc-XXXXXXXXXXXXXXXXX"     ⇐ Current VPC Name
appli_ec2     = "i-YYYYYYYYYYYYYYYYY"       ⇐ ec2 instance on aws
# End
new port, rule priority and host header write into neworg.json file as shown below.




[
    { "port": 9990, "priority": 110, "header": "mydemongo2.dalgo.org" }
]


So if you want to add another org, just add another json entry.


[
    { "port": 9990, "priority": 110, "header": "mydemongo2.dalgo.org" },
    { "port": 8883, "priority": 120, "header": "mydemongo4.dalgo.org" }
]


Similarly if you want to delete an entry, remove a specific json entry.
[
    { "port": 9990, "priority": 110, "header": "mydemongo2.dalgo.org" },
]


Make sure the above port entry should match the CONTAINER_PORT entry , else your superset application and aws configuration will mismatch.


Prerequisite / Execution Environment
================================
Unlike bash and python3 , which are usually installed on the system by default.
Terraform you have to manually install with aws credentials, both are must, because terraform uses aws api’s as part of resource creation on aws infrastructure in your account. 


provider "aws" {
  region     = "ap-south-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  token      = var.aws_session_token
}




1. Create a fresh directory and copy four files, terraform.tfvars.example, variables.tf, main.tf and neworg.json
This is available in platform_infra/Tf4aws directory.
2. Copy terraform.tf.example into terraform.tfvars.
3. Copy your public key on ec2 machine for passwordless ssh execution.
4. Make sure “git”  is available on the local machine.
5. Make sure “psql” command executable from the given remote application server to aws RDS instance.
6. Make sure terraform and aws configured on the local machine.
7. Make sure proper aws credentials, if not configure with “aws configure”.
8. Verify it's configured properly with command “aws sts get-caller-identity”.
9. Before executing the terraform command, make sure to export all three environment variables in the shell. ( viz. $AWS_ACCESS_KEY_ID",”$AWS_SECRET_ACCESS_KEY”,”$AWS_SESSION_TOKEN”  )
10. There are three options we generally use with terraform, ( plan, apply, delete ).
11. terraform plan , shows action on resources  in aws infrastructure account which you have configured as part of “aws configure”.
12. terraform apply, will create resources as mentioned in “main.tf”.
13. terraform destroy, will delete resources mentioned in “main.tf”.


To launch the superset application and configure aws automatically, use below command.
        
        $ terraform init ; terraform fmt ; terraform validate


$ terraform apply --auto-approve -var "aws_access_key=$AWS_ACCESS_KEY_ID" -var "aws_secret_key=$AWS_SECRET_ACCESS_KEY" -var "aws_session_token=$AWS_SESSION_TOKEN"



