# Defaults below apply unless set in terraform.tfvars. Any variable here can be overridden there (e.g. nat_az = "af-south-1b").

########################################
# Account
########################################

variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "af-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile pointing at the prod account (024209611402)"
  type        = string
}

variable "aws_account_id" {
  description = "Prod AWS account ID (provider refuses to run against any other)"
  type        = string
}

########################################
# Network
########################################

variable "vpc_name" {
  description = "Prefix of every Name tag (VPC: <vpc_name>-vpc, NAT: <vpc_name>-nat-gateway, ...)"
  type        = string
  default     = "dalgo-prod-af"
}

# Must not overlap Mumbai prod (172.31.0.0/16, peered) or 10.0.0.0/16 (stale kaapi peering route in the Mumbai main table).
# 10.20 = staging Africa. 10.30 = prod Africa. 10.31/10.32 reserved for later prod regions.
variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.30.0.0/16"
}

# AZ => CIDR. One public + one private subnet per AZ (same layout as staging Africa, 10.20 -> 10.30).
# Data path (RDS, EKS nodes, NAT) is in af-south-1a only: no cross-AZ transfer.
# af-south-1b only adds availability for the EKS control plane and the internal ALB (both need 2 AZs).
# af-south-1c is spare (RDS subnet group); nothing is placed there.
variable "public_subnets" {
  description = "Public subnets (NAT; internet-facing ALBs if ever needed), keyed by AZ"
  type        = map(string)
  default = {
    "af-south-1a" = "10.30.32.0/20"
    "af-south-1b" = "10.30.0.0/20"
    "af-south-1c" = "10.30.16.0/20"
  }
}

variable "private_subnets" {
  description = "Private subnets (EKS ENIs, nodes, internal ALB, RDS), keyed by AZ"
  type        = map(string)
  default = {
    "af-south-1a" = "10.30.48.0/20"
    "af-south-1b" = "10.30.80.0/20"
    "af-south-1c" = "10.30.96.0/20"
  }
}

variable "nat_az" {
  description = "AZ of the public subnet that holds the (single) NAT gateway. Same AZ as the nodes: no cross-AZ NAT traffic."
  type        = string
  default     = "af-south-1a"
}

variable "alb_azs" {
  description = "AZs whose subnets get the kubernetes.io/role/(internal-)elb tag, i.e. where the LB controller puts ALBs (min 2)"
  type        = list(string)
  default     = ["af-south-1a", "af-south-1b"]
}

########################################
# ECR pull-through cache (ecr.tf)
########################################

variable "ecr_docker_hub_prefix" {
  description = "ECR repo prefix for the Docker Hub cache (<account>.dkr.ecr.<region>.amazonaws.com/<prefix>/...). Keep in sync with cluster/terraform."
  type        = string
  default     = "docker-hub"
}

variable "ecr_docker_hub_secret_name" {
  description = "Secrets Manager secret IN af-south-1 with Docker Hub username/accessToken (replica of the Mumbai one, made by hand; must start with ecr-pullthroughcache/)"
  type        = string
  default     = "ecr-pullthroughcache/docker-hub"
}

variable "ecr_cache_max_age_days" {
  description = "Cached images older than this expire (re-fetched from Docker Hub on next pull)"
  type        = number
  default     = 90
}
