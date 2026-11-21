variable "aws_profile" {
  description = "AWS CLI profile pointing at the prod account (024209611402)"
  type        = string
}

variable "aws_account_id" {
  description = "Prod AWS account ID (provider refuses to run against any other)"
  type        = string
}

variable "peering_accepted" {
  description = "false on the first apply. Set true after the peering is accepted in Mumbai (status active): adds the Africa -> Mumbai routes."
  type        = bool
  default     = false
}

########################################
# Mumbai prod facts (hand-built, read with describe calls on 2026-11-21). Only used as values here:
# peering target, CIDR rules, and the printed manual commands. Nothing in Mumbai is modified.
########################################

variable "mumbai_vpc_id" {
  description = "Mumbai prod VPC (dalgo-prod-vpc)"
  type        = string
  default     = "vpc-060665f96234a5997"
}

variable "mumbai_vpc_cidr" {
  description = "Mumbai prod VPC CIDR"
  type        = string
  default     = "172.31.0.0/16"
}

variable "mumbai_ec2_private_ip" {
  description = "dalgo-production-arm (i-031701d000d249f91): Django + Celery + Prefect server. Fixed for the instance's life; changes only if the EC2 is replaced."
  type        = string
  default     = "172.31.2.21"
}

variable "mumbai_ec2_sg_id" {
  description = "ddp-production-server SG on dalgo-production-arm (already allows 4200 from the Mumbai prefect-worker SG). Manual 4200 rule goes here."
  type        = string
  default     = "sg-04d35add536d7604d"
}

variable "mumbai_route_table_id" {
  description = "Route table of the EC2's subnet (subnet-0181641712cc0826a has no explicit association, so it uses the VPC main table). Manual route goes here."
  type        = string
  default     = "rtb-0b63cbb452c6bc882"
}

variable "prefect_port" {
  description = "Prefect server API port on dalgo-production-arm"
  type        = number
  default     = 4200
}
