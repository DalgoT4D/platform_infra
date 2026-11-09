locals {
  name = var.vpc_name
}

########################################
# VPC + internet gateway
########################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # EKS + private R53 zone need both

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-igw"
  }
}

########################################
# Subnets
########################################

# ELB role tags tell the LB controller where to put ALBs: only the var.alb_azs subnets get them.
resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true

  tags = merge(
    { Name = "${local.name}-public-subnet" },
    contains(var.alb_azs, each.key) ? { "kubernetes.io/role/elb" = "1" } : {}, # internet-facing ALBs (Superset, Grafana)
  )
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = merge(
    { Name = "${local.name}-private-subnet" },
    contains(var.alb_azs, each.key) ? { "kubernetes.io/role/internal-elb" = "1" } : {}, # internal ALBs (Airbyte)
  )
}

########################################
# NAT (single, in one public subnet; enough for staging)
########################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.nat_az].id

  tags = {
    Name = "${local.name}-nat-gateway"
  }

  depends_on = [aws_internet_gateway.main]
}

########################################
# Route tables
########################################

# public: 0.0.0.0/0 -> IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name}-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# private: 0.0.0.0/0 -> NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${local.name}-private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

########################################
# S3 gateway endpoint (free)
########################################

# Adds a route for the regional S3 prefix list to both route tables, so S3 traffic
# (Airbyte logs/state, image layers from ECR, RDS backups) skips the NAT ($0.056/GB).
# Only covers buckets in var.aws_region; other-region buckets still go via NAT.
# Requests arrive from private IPs: bucket policies keyed on aws:SourceIp (NAT EIP) stop matching.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id, aws_route_table.public.id]

  tags = {
    Name = "${local.name}-s3-endpoint"
  }
}
