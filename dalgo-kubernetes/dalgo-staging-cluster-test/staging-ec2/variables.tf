# Defaults below apply unless set in terraform.tfvars. Any variable here can be overridden there (e.g. subnet_az = "ap-south-1b").

########################################
# Account
########################################

variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile pointing at the staging account"
  type        = string
}

variable "aws_account_id" {
  description = "Staging AWS account ID (provider refuses to run against any other)"
  type        = string
}

########################################
# Instance (defaults mirror the current dalgo-staging-arm box)
########################################

variable "instance_name" {
  description = "Name tag of the instance"
  type        = string
  default     = "dalgo-staging-ec2"
}

variable "instance_type" {
  description = "EC2 instance type (arm64, must match the AMI)"
  type        = string
  default     = "m6g.large"
}

variable "subnet_az" {
  description = "AZ of the public subnet the box runs in. Same AZ as RDS and the EKS nodes."
  type        = string
  default     = "ap-south-1a"
}

# Latest match is picked on first apply only (ami is in ignore_changes).
variable "ami_name_filter" {
  description = "Canonical AMI name pattern"
  type        = string
  default     = "ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-arm64-server-*"
}

variable "root_volume_size" {
  description = "Root disk size in GiB"
  type        = number
  default     = 40
}

# Current box is unencrypted. Free to turn on for a fresh box; can't be changed in place later.
variable "root_volume_encrypted" {
  description = "Encrypt the root EBS volume"
  type        = bool
  default     = true
}

########################################
# SSH
########################################

# Create in the EC2 console first (Key pairs -> Create key pair); download the .pem once.
variable "key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH into the box"
  type        = string
  default     = "dalgo-staging-key-pair"
}
