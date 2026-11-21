# Only the Airbyte RDS SG lives here. Not copied from Mumbai staging on purpose:
# - EC2 SG / SSH / Cloudflare 443 SGs: no EC2 runs in Africa, nothing is public.
# - EKS: the cluster SG (control plane + nodes) is created by EKS itself; ALB SGs by the LB controller.
# Rules are separate resources (not inline blocks), same as staging Africa.

########################################
# Airbyte RDS (prod-rds/)
########################################

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "dalgo prod africa airbyte rds security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name   = "${local.name}-rds-sg"
    Subset = "airbyte"
  }
}

# 5432 from inside the Africa VPC only (EKS nodes/pods are the only clients).
# CIDR instead of the cluster SG: the cluster SG doesn't exist until cluster/terraform is applied.
# Mumbai VPC (172.31.0.0/16) is NOT allowed. Only exception: the Mumbai prod EC2 /32 (dalgo-production-arm, jump host),
# added as a separate rule by ../peering (rds_from_mumbai_ec2). Keep rules here separate resources,
# or a bootstrap apply would delete that rule.
resource "aws_vpc_security_group_ingress_rule" "rds_from_vpc" {
  security_group_id = aws_security_group.rds.id
  description       = "Postgres from the Africa VPC (EKS)"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = var.vpc_cidr

  tags = {
    Name = "${local.name}-rds-from-vpc"
  }
}

resource "aws_vpc_security_group_egress_rule" "rds_all" {
  security_group_id = aws_security_group.rds.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${local.name}-rds-all-outbound"
  }
}
