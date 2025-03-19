# Execute on a remote machine , create Database and User for client in postgres running on aws RDS

resource "null_resource" "setup_database" {
  connection {
    type        = "ssh"
    user        = var.REMOTE_USER
    private_key = file("${var.SSH_KEY}")
    host        = data.aws_instance.ec2_instance_id.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "echo 'Creating Database and User ' ",
      " PGPASSWORD=${var.POSTGRES_PASSWORD} psql -h ${data.aws_db_instance.PostgresRDS.address} -U ${var.POSTGRES_USER} -c 'CREATE DATABASE ${var.APP_DB_NAME}' ",
      " PGPASSWORD=${var.POSTGRES_PASSWORD} psql -h ${data.aws_db_instance.PostgresRDS.address} -U ${var.POSTGRES_USER} -c \"CREATE USER ${var.APP_DB_USER} WITH PASSWORD '${var.APP_DB_PASS}' \" ",
      " PGPASSWORD=${var.POSTGRES_PASSWORD} psql -h ${data.aws_db_instance.PostgresRDS.address} -U ${var.POSTGRES_USER} -c 'GRANT ALL PRIVILEGES ON DATABASE ${var.APP_DB_NAME} TO ${var.APP_DB_USER}' "
    ]
  }
}
# Login to machine and clone git repository if not present else do a git pull origin main.
resource "null_resource" "clone_repo"{
    connection {
      type        = "ssh"
      user        = var.REMOTE_USER
      private_key = file("${var.SSH_KEY}")
      host        = data.aws_instance.ec2_instance_id.public_ip
    }
    provisioner "remote-exec" {
      inline = [
        # Check if the docker-superset directory exists
        "if [ -d \"docker-superset\" ]; then",
        "  echo 'Repository already exists, checking branch...'",
        "  cd docker-superset",
        "  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)",
        "  if [ \"$CURRENT_BRANCH\" != \"main\" ]; then",
        "    echo 'Not on main branch, switching to main...'",
        "    git checkout main",
        "  fi",
        "  echo 'Pulling latest changes from main branch...'",
        "  git pull origin main",
        "else",
        "  echo 'Repository not found, cloning it now...'",
        "  git clone https://github.com/DalgoT4D/docker-superset.git",
        "fi"
      ]
    }
}

resource "null_resource" "cd_to_generatclient" {
  depends_on = [null_resource.clone_repo]
  connection {
    type        = "ssh"
    user        = var.REMOTE_USER
    private_key = file("${var.SSH_KEY}")
    host        = data.aws_instance.ec2_instance_id.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "cd \"${var.CLONED_PARENT_DIR}/${var.SUPERSET_MAKE_CLIENT_DIR}\"",
      "chmod +x generate-make-client.sh"
    ]
  }
}
# Execute Superset Client Generation Script
resource "null_resource" "generate_client" {
  depends_on = [null_resource.cd_to_generatclient]
  connection {
    type        = "ssh"
    user        = var.REMOTE_USER
    private_key = file("${var.SSH_KEY}")
    host        = data.aws_instance.ec2_instance_id.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "cd \"${var.CLONED_PARENT_DIR}/${var.SUPERSET_MAKE_CLIENT_DIR}\"",
      "chmod +x ./generate-make-client.sh",
      "./generate-make-client.sh ${var.CLIENT_NAME} ${var.PROJECT_OR_ENV} ${var.BASE_IMAGE} ${var.SUPERSET_VERSION} ${var.OUTPUT_IMAGE_TAG} ${var.CONTAINER_PORT} ${var.CELERY_FLOWER_PORT} ${var.ARCH_TYPE} ${var.OUTPUT_DIR}"
    ]
  }

}

# Update Superset env file with sed
# Addbelow line when you are using docker based postgres on ec2 machine
# -e 's#^SQLALCHEMY_DATABASE_URI=.*#SQLALCHEMY_DATABASE_URI=postgresql://${var.POSTGRES_USER}:${var.POSTGRES_PASSWORD}@172.18.0.2/${var.APP_DB_NAME}#' \
resource "null_resource" "update_superset_env" {
  depends_on = [null_resource.generate_client]

  connection {
    type        = "ssh"
    user        = var.REMOTE_USER
    private_key = file("${var.SSH_KEY}")
    host        = data.aws_instance.ec2_instance_id.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Detecting OS and setting sed syntax...'",
      "if sed --version 2>/dev/null | grep -q GNU; then SED_CMD='sed -i'; else SED_CMD='sed -i \"\"'; fi",
      
      "cd ${var.CLONED_PARENT_DIR}/${var.SUPERSET_MAKE_CLIENT_DIR}/${var.OUTPUT_DIR}",
      
      "$SED_CMD 's/^SUPERSET_SECRET_KEY=.*/SUPERSET_SECRET_KEY=${var.SUPERSET_SECRET_KEY}/' superset.env",
      "$SED_CMD 's/^SUPERSET_ADMIN_USERNAME=.*/SUPERSET_ADMIN_USERNAME=${var.SUPERSET_ADMIN_USERNAME}/' superset.env",
      "$SED_CMD 's/^SUPERSET_ADMIN_PASSWORD=.*/SUPERSET_ADMIN_PASSWORD=${var.SUPERSET_ADMIN_PASSWORD}/' superset.env",
      "$SED_CMD 's/^SUPERSET_ADMIN_EMAIL=.*/SUPERSET_ADMIN_EMAIL=${var.SUPERSET_ADMIN_EMAIL}/' superset.env",
      "$SED_CMD 's/^POSTGRES_USER=.*/POSTGRES_USER=${var.POSTGRES_USER}/' superset.env",
      "$SED_CMD 's/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${var.POSTGRES_PASSWORD}/' superset.env",
      "$SED_CMD 's/^APP_DB_USER=superset/APP_DB_USER=${var.APP_DB_USER}/' superset.env",
      "$SED_CMD 's/^APP_DB_PASS=.*/APP_DB_PASS=${var.APP_DB_PASS}/' superset.env",
      "$SED_CMD 's/^APP_DB_NAME=superset.*/APP_DB_NAME=${var.APP_DB_NAME}/' superset.env",
      "$SED_CMD 's/ENABLE_OAUTH=1/ENABLE_OAUTH=/' superset.env",
      "$SED_CMD 's#^SQLALCHEMY_DATABASE_URI=.*#SQLALCHEMY_DATABASE_URI=postgresql://${var.POSTGRES_USER}:${var.POSTGRES_PASSWORD}@${data.aws_db_instance.PostgresRDS.address}/${var.APP_DB_NAME}#' superset.env"
    ]
  }
}




# Three commands we usually execute for docker-superset, (viz . docker build, docker compose, create admin user)
resource "null_resource" "remote_build" {
  depends_on = [null_resource.update_superset_env]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("${var.SSH_KEY}")
    host        = data.aws_instance.ec2_instance_id.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Creating container with new client...'",
      "cd ${var.CLONED_PARENT_DIR}/${var.SUPERSET_MAKE_CLIENT_DIR}/${var.OUTPUT_DIR} && chmod +x build.sh && ./build.sh",
      "sleep 5",
      "cd ${var.CLONED_PARENT_DIR}/${var.SUPERSET_MAKE_CLIENT_DIR}/${var.OUTPUT_DIR} && docker compose -f docker-compose.yml up -d",
      "sleep 5",
      "cd ${var.CLONED_PARENT_DIR}/${var.SUPERSET_MAKE_CLIENT_DIR}/${var.OUTPUT_DIR} && chmod +x start-superset.sh && bash start-superset.sh"
    ]
  }
}


# Main Task of the script is below two items
# One rule for redirection will be added onto current port 443's exisiting rule with given header as input
# One new port will be added onto ec2 security groups inbound rule
# if you see prefix as "var" means its a input variable

# This script takes following inputs from terraform.tfvars
# variables are defined in variables.tf

# alb_name      = "XXXXXX"               (      ALBName         )
# cur_vpc       = "vpc-XXXXXXXXXXXXXXX"  (      vpc id          )
# neworg_port   = XXXX                   (      9990            )
# appli_ec2     = "i-XXXXXXXXXXXXXXXXX"  (  ec2 instance id     )
# neworg_name   = "XXXXXXXXXXXXXXXXXX"   (  mydemongo.dalgo.in  )
# rule_priority = XXXX                   (      90              )

# Assume region is ap-south-1 else please change as applicable

provider "aws" {
  region     = "ap-south-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  token      = var.aws_session_token
}

# Read data from neworgs.json for port, rule_priority and Host header

locals {
  neworg_config = jsondecode(file("neworg.json"))
}

# Get Reference for RDS database
data "aws_db_instance" "PostgresRDS" {
  db_instance_identifier = var.rdsname
}
# Get Data for existing load balancer

data "aws_lb" "curalb" {
  name = var.alb_name
}

# Get reference for port 443 rule existing on load balancer

data "aws_lb_listener" "selected443" {
  load_balancer_arn = data.aws_lb.curalb.arn
  port              = 443
}

# Append rule for forward on existing port 443 rule with host header received as input

resource "aws_lb_listener_rule" "neworg_listener_rule" {

  listener_arn = data.aws_lb_listener.selected443.arn

  for_each = { for rule in local.neworg_config : rule.port => rule }
  priority = each.value.priority
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.neworg_tgt_group[each.key].arn
  }
  condition {
    host_header {
      values = [each.value.header]
    }
  }
}


# Create target group needed for new port and health check
# Assuming application is running as HTTPS or HTTP
# for superset its HTTP

resource "aws_lb_target_group" "neworg_tgt_group" {
  for_each = { for rule in local.neworg_config : rule.port => rule }
  name     = "${var.CLIENT_NAME}-tg-${each.value.port}"
  port     = each.value.port
  protocol = "HTTP"
  vpc_id   = var.cur_vpc

  health_check {
    interval            = 30
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
  tags = {
    Name = "Superset-tgt-grp-${each.value.port}"
  }
}


# Register newly created target group with new port onto ec2 instance received as input

resource "aws_lb_target_group_attachment" "neworg_register_ec2" {
  for_each         = { for rule in local.neworg_config : rule.port => rule }
  target_group_arn = aws_lb_target_group.neworg_tgt_group[each.key].arn
  target_id        = var.appli_ec2
  port             = each.value.port
}


# Get ec2 instance id from ec2 name received as input variable

data "aws_instance" "ec2_instance_id" {
  instance_id = var.appli_ec2
}

# Get existing security id on ec2 instance received as input

data "aws_security_group" "ec2_sg" {
  # Assume we are adding into appli_ec2 instance and has at least one security group
  id = tolist(data.aws_instance.ec2_instance_id.vpc_security_group_ids)[0]
}

# Reference the existing security group that allows all traffic from the ALB
data "aws_security_group" "allow_all_from_alb" {
  id = var.alb_sg
}

# Attach the ALB's security group to the primary network interface of the EC2 instance. 
resource "aws_network_interface_sg_attachment" "sg_attachment" {
  security_group_id    = data.aws_security_group.allow_all_from_alb.id
  network_interface_id = data.aws_instance.ec2_instance_id.network_interface_id  # Primary network interface
}

# Output the status
output "status" {
  value = "Remote Docker deployment completed."
}