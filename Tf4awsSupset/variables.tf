variable "AUTOROOT_DIR" { type = string }
variable "REMOTE_USER" { type = string }
variable "SSH_KEY" { type = string }
variable "CLONED_PARENT_DIR" { type = string }
variable "SUPERSET_MAKE_CLIENT_DIR" { type = string }
variable "CLIENT_NAME" { type = string }
variable "PROJECT_OR_ENV" { type = string }
variable "BASE_IMAGE" { type = string }
variable "SUPERSET_VERSION" { type = string }
variable "OUTPUT_IMAGE_TAG" { type = string }
variable "CONTAINER_PORT" { type = string }
variable "CELERY_FLOWER_PORT" { type = string }
variable "ARCH_TYPE" { type = string }
variable "OUTPUT_DIR" { type = string }
variable "SUPERSET_SECRET_KEY" {type = string}
variable "SUPERSET_ADMIN_USERNAME" { type = string }
variable "SUPERSET_ADMIN_PASSWORD" { type = string }
variable "SUPERSET_ADMIN_EMAIL" { type = string }
variable "POSTGRES_USER" { type = string }
variable "POSTGRES_PASSWORD" { type = string }
variable "APP_DB_USER" { type = string }
variable "APP_DB_PASS" { type = string }
variable "APP_DB_NAME" { type = string }
variable "ENABLE_OAUTH" { type = string }
variable "cur_vpc" {
  description = "this is our VPC which could be isolated from other VPCs"
  type        = string
}
variable "alb_name" {
  description = "this is our Current Application load Balancer"
  type        = string
}
variable "neworg_port" {
  description = "this is new port for which we need to create the target group and security group and add it to ALB and ec2 instance"
  type        = string
}
variable "appli_ec2" {
  description = "this is ec2 instance where application is UP and RUNNING on New port"
  type        = string
}
variable "neworg_name" {
  description = "this is domain name of new Customer for which superset application is to be deployed"
  type        = string
}
variable "rule_priority" {
  description = "this is priority for the rule which has to be added in port 443"
  type        = string
}
variable "aws_access_key" {
  type = string
}
variable "aws_secret_key" {
  type = string
}
variable "aws_session_token" {
  type    = string
  default = ""
}
variable "rdsname" {
  type = string
}
