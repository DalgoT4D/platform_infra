########################################
# Network from bootstrap state (VPC, subnets, SGs created in ../../bootstrap)
########################################

data "terraform_remote_state" "bootstrap" {
  backend = "s3"

  config = {
    bucket  = "test-terraform-state-and-lock-bucket"
    key     = "test/bootstrap/dalgo-staging/terraform.tfstate"
    region  = "ap-south-1"
    profile = "dalgo-staging-admin"
  }
}

# ELB role tags on the subnets are set in bootstrap (aws_subnet tags), not here.
locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs

  vpc_id             = local.bootstrap.vpc_id
  cluster_subnet_ids = [for az in var.cluster_subnet_azs : local.bootstrap.private_subnet_ids[az]]
  node_subnet_ids    = [for az in var.node_subnet_azs : local.bootstrap.private_subnet_ids[az]]
  staging_ec2_sg_id  = local.bootstrap.staging_ec2_sg_id
  rds_sg_id          = local.bootstrap.rds_sg_id
}

########################################
# ALB support (ALBs themselves come from Ingresses via the LB controller)
########################################

# TLS cert for the ALBs. Validate via the CNAME in `acm_validation_records` (Cloudflare, DNS only).
resource "aws_acm_certificate" "wildcard" {
  domain_name       = var.acm_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    # "*" not allowed in tag values
    Name = "test-${replace(var.acm_domain, "*", "wildcard")}"
  }
}

# Internal airbyte name, resolvable only inside the VPC. Alias record -> ALB is added by hand.
resource "aws_route53_zone" "airbyte_internal" {
  name    = var.airbyte_internal_domain
  comment = "Private zone for the internal airbyte ALB"

  # delete even with the hand-made alias record
  force_destroy = true

  vpc {
    vpc_id = local.vpc_id
  }
}
