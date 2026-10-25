# Rules are separate resources (not inline blocks) on purpose: other stacks add rules to these SGs
# (cluster/terraform adds "4200 from cluster SG" to the staging EC2 SG). Inline blocks would delete them.

########################################
# Staging EC2 (backend, webapp, Prefect server box)
########################################

resource "aws_security_group" "staging_ec2" {
  name        = "${local.name}-ec2-sg"
  description = "sg for dalgo staging machine"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-ec2-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "staging_ec2_ssh" {
  for_each = toset(var.ssh_ingress_cidrs)

  security_group_id = aws_security_group.staging_ec2.id
  description       = "SSH"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value

  tags = {
    Name = "${local.name}-ec2-ssh-${each.value}"
  }
}

resource "aws_vpc_security_group_egress_rule" "staging_ec2_all" {
  security_group_id = aws_security_group.staging_ec2.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${local.name}-ec2-all-outbound"
  }
}

########################################
# Staging RDS (cluster/terraform adds "5432 from cluster SG")
########################################

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "dalgo staging rds security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-rds-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_staging_ec2" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Allow postgresql traffic from ec2 sg"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.staging_ec2.id

  tags = {
    Name = "${local.name}-rds-from-ec2"
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

########################################
# HTTPS from Cloudflare only (sites are proxied through Cloudflare)
########################################

# No egress rules: attached next to staging_ec2, which allows all outbound.
resource "aws_security_group" "cloudflare_https" {
  name        = "${local.name}-whitelist-cloudflare-ip-range-https"
  description = "allow cloudflare ip range on https"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-whitelist-cloudflare-ip-range-https"
  }
}

resource "aws_vpc_security_group_ingress_rule" "cloudflare_https_v4" {
  for_each = toset(var.cloudflare_ipv4_ranges)

  security_group_id = aws_security_group.cloudflare_https.id
  description       = "Cloudflare IPv4 range"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value

  tags = {
    Name = "${local.name}-cloudflare-https-${each.value}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "cloudflare_https_v6" {
  for_each = toset(var.cloudflare_ipv6_ranges)

  security_group_id = aws_security_group.cloudflare_https.id
  description       = "Cloudflare IPv6 range"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = each.value

  tags = {
    Name = "${local.name}-cloudflare-https-${each.value}"
  }
}
