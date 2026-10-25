# Defaults below apply unless set in terraform.tfvars. Any variable here can be overridden there (e.g. nat_az = "ap-south-1b").

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
# Network (defaults mirror the current staging VPC)
########################################

variable "vpc_name" {
  description = "Prefix of every Name tag (VPC: <vpc_name>-vpc, NAT: <vpc_name>-nat-gateway, ...)"
  type        = string
  default     = "dalgo-staging"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "172.31.0.0/16"
}

# AZ => CIDR. One public + one private subnet per AZ.
# Data path (EC2, RDS, EKS nodes, NAT) is in ap-south-1a only: no cross-AZ transfer.
# ap-south-1b only adds availability for the EKS control plane and the ALBs (both need 2 AZs).
# ap-south-1c is spare (RDS subnet group and future use); nothing is placed there.
variable "public_subnets" {
  description = "Public subnets (internet-facing ALBs, NAT, staging EC2), keyed by AZ"
  type        = map(string)
  default = {
    "ap-south-1a" = "172.31.32.0/20"
    "ap-south-1b" = "172.31.0.0/20"
    "ap-south-1c" = "172.31.16.0/20"
  }
}

variable "private_subnets" {
  description = "Private subnets (EKS ENIs, nodes, internal ALB), keyed by AZ"
  type        = map(string)
  default = {
    "ap-south-1a" = "172.31.48.0/20"
    "ap-south-1b" = "172.31.80.0/20"
    "ap-south-1c" = "172.31.96.0/20"
  }
}

variable "nat_az" {
  description = "AZ of the public subnet that holds the (single) NAT gateway. Same AZ as the nodes: no cross-AZ NAT traffic."
  type        = string
  default     = "ap-south-1a"
}

variable "alb_azs" {
  description = "AZs whose subnets get the kubernetes.io/role/(internal-)elb tag, i.e. where the LB controller puts ALBs (min 2)"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

########################################
# Security groups
########################################

variable "ssh_ingress_cidrs" {
  description = "CIDRs allowed to SSH (22) into the staging EC2"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# https://www.cloudflare.com/ips-v4
variable "cloudflare_ipv4_ranges" {
  description = "Cloudflare IPv4 ranges allowed on 443"
  type        = list(string)
  default = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ]
}

# https://www.cloudflare.com/ips-v6
variable "cloudflare_ipv6_ranges" {
  description = "Cloudflare IPv6 ranges allowed on 443"
  type        = list(string)
  default = [
    "2400:cb00::/32",
    "2606:4700::/32",
    "2803:f800::/32",
    "2405:b500::/32",
    "2405:8100::/32",
    "2a06:98c0::/29",
    "2c0f:f248::/32",
  ]
}
