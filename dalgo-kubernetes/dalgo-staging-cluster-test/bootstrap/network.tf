########################################
# VPC + internet gateway
########################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # EKS + private R53 zone need both

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

########################################
# Subnets
########################################

# ELB role tags tell the LB controller where to put ALBs.
# NOTE: cluster/terraform still sets the same tags with aws_ec2_tag. Same values, so no conflict;
# a cluster destroy removes them and the next apply here puts them back.
resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true

  tags = {
    Name                     = "test-public-subnet-${each.key}"
    "kubernetes.io/role/elb" = "1" # internet-facing ALBs (Superset, Grafana)
  }
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    Name                              = "test-private-subnet-${each.key}"
    "kubernetes.io/role/internal-elb" = "1" # internal ALBs (Airbyte)
  }
}

########################################
# NAT (single, in one public subnet; enough for staging)
########################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "test-staging-nat-elastic-ip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.nat_az].id

  tags = {
    Name = "test-staging-nat-gateway"
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
    Name = "test-public-route-table"
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
    Name = "test-private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
