########################################
# Existing VPC (created outside terraform)
########################################

data "aws_vpc" "current_vpc" {
  id = var.vpc_id
}

data "aws_subnet" "cluster_subnets" {
  count = length(var.cluster_subnet_ids)
  id    = var.cluster_subnet_ids[count.index]
}

# Subnet tags the LB controller uses to place ALBs (tags only; subnets stay unmanaged).
resource "aws_ec2_tag" "public_subnet_elb" {
  for_each = toset(var.public_subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/role/elb" # internet-facing ALBs (Superset, Grafana)
  value       = "1"
}

resource "aws_ec2_tag" "private_subnet_internal_elb" {
  for_each = toset(var.private_subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb" # internal ALBs (Airbyte)
  value       = "1"
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
    Name = replace(var.acm_domain, "*", "wildcard")
  }
}

# Internal airbyte name, resolvable only inside the VPC. Alias record -> ALB is added by hand.
resource "aws_route53_zone" "airbyte_internal" {
  name    = var.airbyte_internal_domain
  comment = "Private zone for the internal airbyte ALB"

  # delete even with the hand-made alias record
  force_destroy = true

  vpc {
    vpc_id = data.aws_vpc.current_vpc.id
  }
}
