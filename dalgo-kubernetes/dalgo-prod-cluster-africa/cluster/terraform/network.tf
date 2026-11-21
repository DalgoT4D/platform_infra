########################################
# Network from the AFRICA bootstrap state (VPC, subnets created in ../../bootstrap)
########################################

data "terraform_remote_state" "bootstrap" {
  backend = "s3"

  config = {
    bucket  = "production-eks-terraform-state"
    key     = "dalgo-prod-af/bootstrap/terraform.tfstate"
    region  = "ap-south-1" # state bucket region
    profile = "dalgo-prod-admin"
  }
}

# ELB role tags on the subnets are set in bootstrap (aws_subnet tags), not here.
locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs

  vpc_id             = local.bootstrap.vpc_id
  cluster_subnet_ids = [for az in var.cluster_subnet_azs : local.bootstrap.private_subnet_ids[az]]
  node_subnet_ids    = [for az in var.node_subnet_azs : local.bootstrap.private_subnet_ids[az]]
}

########################################
# ALB support (ALBs themselves come from Ingresses via the LB controller). Same as Mumbai.
########################################

# TLS cert for the Africa ALB. ACM is regional: the Mumbai cert can't be used here.
# Validate via the CNAME in `acm_validation_records` (Cloudflare, DNS only). For the same domain in the
# same account ACM usually reuses the CNAME already added for Mumbai; if the output differs, add it.
resource "aws_acm_certificate" "wildcard" {
  domain_name       = var.acm_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    # "*" not allowed in tag values
    Name = "dalgo-prod-af-${replace(var.acm_domain, "*", "wildcard")}"
  }
}

# Internal Airbyte name -> Africa internal ALB. Private zone: resolvable only from associated VPCs.
# Africa VPC here; the Mumbai prod VPC (where the backend EC2 asks) is associated BY HAND (../../README.md).
# Alias record -> ALB is added by hand after the ingress exists (same as Mumbai).
resource "aws_route53_zone" "airbyte_internal" {
  name    = var.airbyte_internal_domain
  comment = "Private zone for the Africa internal airbyte ALB"

  # delete even with the hand-made alias record
  force_destroy = true

  vpc {
    vpc_id = local.vpc_id
  }

  # The Mumbai prod VPC association is made by hand (console/CLI);
  # without this, every apply here would remove it.
  lifecycle {
    ignore_changes = [vpc]
  }

  tags = {
    Name   = var.airbyte_internal_domain
    Subset = "airbyte"
  }
}
