**Procedure to use terraform scripts for “superset” deployment.**

**Script  Overview :** 

It consists of two sections, one making applications available on the given remote application server and second creating resources on aws infrastructure or configure aws components in such a way that http traffic from client are redirected via load balancer to application running on ec2 instance.

**First part**  
 

1. Pulling the latest “docker-superset” repo from github viz.

https://github.com/DalgoT4D/docker-superset.git

2. Generate\_make\_client                                    ⇐  **take input from** **terraform.tfvars**   
3. Updates “**superset.env**”                                 ⇐  **take input from** **terraform.tfvars**  
4. Ship entire repo to remote machine with **docker-compose.yml** and **superset.env**.  
5. Execute build.sh                                             \<= **build container onto remote machine**.  
6. docker compose                                             \<= **launch application**  
7. start-superset.sh                                             \<= **create admin user and db migration**

**Second Part**

1. Adding listener rule to **existing** HTTP 443 port of given load balancer.  
2. Adding ingress inbound rule onto **existing** security group of Application server.

**Terraform.tfvars**

**\# Below parameters are needed for script execution**

**Location of script directory, terraform will be execute from here**  
**AUTOROOT\_DIR        \= "/home/XXXX/YYYY"**

**Remote user login on application server ( usually it's “ubuntu” )**  
**REMOTE\_USER         \= "ubuntu"**

**SSH Key on local machine**  
**SSH\_KEY             \= "/home/XXX/.ssh/id\_rsa.pem"**

**Local directory where repo is copied,will be deleted at every execution**  
**LOCAL\_CLONE\_DIR     \= "/home/XXX/YYY/superset-repo"**

**Superserset, don’t want to hardcode, incase of future changes**  
**SUPERSET\_MIDDLE\_DIR \= "gensuperset/make-client"**

**Remote machine directory, where repo is copied**  
**So superset.env, will be available in /home/ubuntu/gensuperset/make-client/testngo1/superset.env**

**REMOTE\_CLONE\_DIR    \= "/home/ubuntu"**

**RDS name used in your aws environment**  
**rdsname             \= "rail-db-1"**

**\# End**

**\# Below parameters are for Generate make client**

**CLIENT\_NAME        \= "testngo1"**  
**PROJECT\_OR\_ENV     \= "prod"**  
**BASE\_IMAGE         \= "tech4dev/superset:4.1.1"**  
**SUPERSET\_VERSION   \= "4"**  
**OUTPUT\_IMAGE\_TAG   \= "1.1"**  
**CONTAINER\_PORT     \= "9990"**  
**CELERY\_FLOWER\_PORT \= "5555"**  
**ARCH\_TYPE          \= "linux/amd64"**  
**OUTPUT\_DIR         \= "testngo1"**

**\# End**

**\# Below Parameters are needed for superset.env**

**SUPERSET\_ADMIN\_USERNAME \= "YYY"               ⇐ Client GUI login name**  
**SUPERSET\_ADMIN\_PASSWORD \= "XXXX"			  ⇐ Client GUI password**  
**SUPERSET\_ADMIN\_EMAIL    \= "[admin@ngo.org](mailto:admin@ngo.org)"	  ⇐ Client mail**  
**POSTGRES\_USER           \= "XXXX"		  ⇐ Postgres login**  
**POSTGRES\_PASSWORD       \= "YYYYY"           ⇐ Postgres password**  
**APP\_DB\_USER             \= "XXXXX\_testngo1"   ⇐ Client user for app**  
**APP\_DB\_PASS             \= "testngo1"		  ⇐ Client passwd for app**  
**APP\_DB\_NAME             \= "XXXXX\_testngo1"   ⇐ Client database**  
**ENABLE\_OAUTH            \= ""				  ⇐ Empty as of now**

**\# End**

**\# Below Parameters required for aws resource creation**

**alb\_name      \= "rails-alb-1  "             ⇐ Load Balancer name**  
**cur\_vpc       \= "vpc-089322ce84dece2ca"     ⇐ Current VPC Name**  
**appli\_ec2     \= "i-07556a1aecde2f58d"       ⇐ ec2 instance on aws**  
**\# End**  
**new port, rule priority and host header write into neworg.json file as shown below.**

\[  
    { "port": 9990, "priority": 110, "header": "mydemongo2.dalgo.in" }  
\]

So if you want to add another org, just add another json entry.

\[  
    { "port": 9990, "priority": 110, "header": "mydemongo2.dalgo.in" },  
    { "port": 8883, "priority": 120, "header": "mydemongo4.dalgo.in" }  
\]

Similarly if you want to delete an entry, remove a specific json entry.  
\[  
    { "port": 9990, "priority": 110, "header": "mydemongo2.dalgo.in" },  
\]

Make sure the above **port** entry should match the CONTAINER\_PORT entry , else your superset application and aws configuration will **mismatch**.

**Prerequisite / Execution Environment**  
\================================  
Unlike bash and python3 , which are usually installed on the system by default.  
Terraform you have to manually install with aws credentials, both are must, because terraform uses aws api’s as part of resource creation on aws infrastructure in your account. 

provider "aws" {  
  region     \= "ap-south-1"  
  access\_key \= var.aws\_access\_key  
  secret\_key \= var.aws\_secret\_key  
  token      \= var.aws\_session\_token  
}

1. Create a fresh directory and copy four files, **terraform.tfvars.example, variables.tf, main.tf and neworg.json**  
   This is available in platform\_infra/Tf4aws directory.  
2. Copy terraform.tf.example into terraform.tfvars.  
3. Copy your public key on ec2 machine for passwordless ssh execution.  
4. Make sure “git”  is available on the local machine.  
5. Make sure “psql” command executable from the given remote application server to aws RDS instance.  
6. Make sure terraform and aws configured on the local machine.  
7. Make sure proper aws credentials, if not configure with “aws configure”.  
8. Verify it's configured properly with command “aws sts get-caller-identity”.  
9. Before executing the terraform command, make sure to export all three environment variables in the shell. ( viz. ***$AWS\_ACCESS\_KEY\_ID",”$AWS\_SECRET\_ACCESS\_KEY”,”$AWS\_SESSION\_TOKEN”  )***  
10. There are three options we generally use with terraform, ( plan, apply, delete ).  
11. terraform plan , shows action on resources  in aws infrastructure account which you have configured as part of “aws configure”.  
12. terraform apply, will create resources as mentioned in “main.tf”.  
13. terraform destroy, will delete resources mentioned in “main.tf”.  
    

To launch the superset application and configure aws automatically, use below command.  
	  
	$ ***terraform init ; terraform fmt ; terraform validate***

***$ terraform apply \--auto-approve \-var "aws\_access\_key=$AWS\_ACCESS\_KEY\_ID" \-var "aws\_secret\_key=$AWS\_SECRET\_ACCESS\_KEY" \-var "aws\_session\_token=$AWS\_SESSION\_TOKEN"***

**Note: Useful Links**

1. **Below links shows how to install terraform, aws and has tutorials as well.**

[Install Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) 

2. **aws provider documentation is available below.**

[AWS Provider \- hashicorp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

