########################################
# Remote state (read only). All in the one state bucket (ap-south-1).
########################################

# Mumbai bootstrap: vpc_id, vpc_cidr, public/private_route_table_id, staging_ec2_sg_id
data "terraform_remote_state" "mumbai_bootstrap" {
  backend = "s3"

  config = {
    bucket  = "terraform-state-and-lock-bucket"
    key     = "dalgo-staging/bootstrap/terraform.tfstate" # Mumbai key: READ ONLY here (data source)
    region  = "ap-south-1"
    profile = "dalgo-staging-admin"
  }
}

# Mumbai staging EC2: private_ip (only re-exported as an output, to fill the YAML placeholders)
data "terraform_remote_state" "mumbai_staging_ec2" {
  backend = "s3"

  config = {
    bucket  = "terraform-state-and-lock-bucket"
    key     = "dalgo-staging/staging-ec2/terraform.tfstate" # Mumbai key: READ ONLY here (data source)
    region  = "ap-south-1"
    profile = "dalgo-staging-admin"
  }
}

# Africa bootstrap: vpc_id, vpc_cidr, public/private_route_table_id
data "terraform_remote_state" "africa_bootstrap" {
  backend = "s3"

  config = {
    bucket  = "terraform-state-and-lock-bucket"
    key     = "dalgo-staging-af/bootstrap/terraform.tfstate"
    region  = "ap-south-1"
    profile = "dalgo-staging-admin"
  }
}

# Africa EKS: cluster_security_group_id (SSH rule below). Apply cluster/terraform before this folder.
data "terraform_remote_state" "africa_eks" {
  backend = "s3"

  config = {
    bucket  = "terraform-state-and-lock-bucket"
    key     = "dalgo-staging-af/eks/terraform.tfstate"
    region  = "ap-south-1"
    profile = "dalgo-staging-admin"
  }
}

locals {
  mumbai = data.terraform_remote_state.mumbai_bootstrap.outputs
  africa = data.terraform_remote_state.africa_bootstrap.outputs
}

########################################
# 1. Peering. Inter-region: the requester can't auto_accept, so the Africa side accepts.
########################################

resource "aws_vpc_peering_connection" "mumbai_africa" {
  provider = aws.mumbai

  vpc_id      = local.mumbai.vpc_id
  peer_vpc_id = local.africa.vpc_id
  peer_region = "af-south-1"
  # peer_owner_id omitted: same account

  tags = {
    Name = "dalgo-staging-mumbai-af-peering"
    Side = "requester"
  }

  lifecycle {
    precondition {
      condition     = try(local.mumbai.public_route_table_id, null) != null && try(local.mumbai.private_route_table_id, null) != null
      error_message = "Mumbai bootstrap state has no public/private_route_table_id outputs: apply dalgo-staging-cluster/bootstrap (aws_route conversion + outputs) first."
    }
    precondition {
      condition     = local.mumbai.vpc_cidr != local.africa.vpc_cidr
      error_message = "Mumbai and Africa VPC CIDRs overlap; peering needs distinct CIDRs."
    }
  }
}

resource "aws_vpc_peering_connection_accepter" "mumbai_africa" {
  provider = aws.africa

  vpc_peering_connection_id = aws_vpc_peering_connection.mumbai_africa.id
  auto_accept               = true

  tags = {
    Name = "dalgo-staging-mumbai-af-peering"
    Side = "accepter"
  }
}

########################################
# 2. Routes, as separate resources. Both bootstraps declare routes only as aws_route (no inline
#    route {} blocks), so a bootstrap apply never removes them.
########################################

# Mumbai -> Africa: public (the staging EC2 lives there) + private (EKS pods, not strictly needed today).
resource "aws_route" "mumbai_to_africa" {
  provider = aws.mumbai
  for_each = {
    public  = local.mumbai.public_route_table_id
    private = local.mumbai.private_route_table_id
  }

  route_table_id            = each.value
  destination_cidr_block    = local.africa.vpc_cidr # 10.20.0.0/16
  vpc_peering_connection_id = aws_vpc_peering_connection.mumbai_africa.id

  depends_on = [aws_vpc_peering_connection_accepter.mumbai_africa]
}

# Africa -> Mumbai: private (nodes, pods, internal ALB) + public (symmetry; nothing runs there but the NAT).
resource "aws_route" "africa_to_mumbai" {
  provider = aws.africa
  for_each = {
    public  = local.africa.public_route_table_id
    private = local.africa.private_route_table_id
  }

  route_table_id            = each.value
  destination_cidr_block    = local.mumbai.vpc_cidr # 172.31.0.0/16
  vpc_peering_connection_id = aws_vpc_peering_connection.mumbai_africa.id

  depends_on = [aws_vpc_peering_connection_accepter.mumbai_africa]
}

########################################
# 3. Prefect server API (4200) on the Mumbai staging EC2, from Africa workers + flow-run pods.
#    CIDR, not an SG reference: SG references don't work across regions.
#    Safe as a separate rule: Mumbai's staging_ec2 SG has no inline ingress blocks (all its rules are
#    separate aws_vpc_security_group_*_rule resources), so a Mumbai bootstrap apply won't remove it.
########################################

resource "aws_vpc_security_group_ingress_rule" "prefect_from_africa" {
  provider = aws.mumbai

  security_group_id = local.mumbai.staging_ec2_sg_id
  description       = "Prefect server API from Africa EKS (workers + flow runs)"
  ip_protocol       = "tcp"
  from_port         = var.prefect_port
  to_port           = var.prefect_port
  cidr_ipv4         = local.africa.vpc_cidr

  tags = {
    Name   = "dalgo-staging-prefect-from-af"
    Subset = "prefect"
  }
}

# Airbyte API on the Africa side needs no SG rule from this folder: the Mumbai EC2 reaches it via the
# internal ALB, whose SG the LB controller creates from the inbound-cidrs annotation (Mumbai EC2 /32 only).

########################################
# 4. Africa Airbyte RDS (5432) from the Mumbai staging EC2 only: the EC2 is the one jump host for
#    every region's DB (ssh -L from a laptop), so no bastion per region.
#    /32, not 172.31.0.0/16: Mumbai EKS pods and anything else in the Mumbai VPC stay blocked.
#    Here (not in Africa bootstrap) because it needs the peering + the Mumbai EC2 IP: destroying this
#    folder removes the access with the link. EC2 replaced (new private IP) -> re-apply this folder.
#    Safe as a separate rule: the Africa RDS SG has no inline ingress blocks.
########################################

resource "aws_vpc_security_group_ingress_rule" "rds_from_mumbai_ec2" {
  provider = aws.africa

  security_group_id = local.africa.rds_sg_id
  description       = "Postgres from Mumbai staging EC2 (jump host) over peering"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = "${data.terraform_remote_state.mumbai_staging_ec2.outputs.private_ip}/32"

  tags = {
    Name   = "dalgo-staging-af-rds-from-mumbai-ec2"
    Subset = "airbyte"
  }
}

########################################
# 5. SSH (22) into Africa EKS nodes from the Mumbai staging EC2 only (jump host), over peering.
#    On the cluster SG, which every managed node carries. Key pair: cluster/terraform var.ssh_key_name.
#    Usage, on the Mumbai EC2: ssh -i <af key>.pem ec2-user@<africa node private IP>
#    EC2 replaced (new private IP) -> re-apply this folder.
########################################

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_ssh_from_mumbai_ec2" {
  provider = aws.africa

  security_group_id = data.terraform_remote_state.africa_eks.outputs.cluster_security_group_id
  description       = "SSH from Mumbai staging EC2 (jump host) over peering"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "${data.terraform_remote_state.mumbai_staging_ec2.outputs.private_ip}/32"

  tags = {
    Name = "dalgo-staging-af-eks-ssh-from-mumbai-ec2"
  }
}

########################################
# 6. Africa Airbyte private zone (airbyte-staging-af-internal.dalgo.org) -> also the Mumbai VPC,
#    so the backend EC2 resolves the name to the Africa internal ALB's private IPs (reached over peering).
#    Zone is created in ../cluster/terraform (with ignore_changes = [vpc] so this survives).
########################################

resource "aws_route53_zone_association" "airbyte_af_internal_mumbai" {
  provider = aws.mumbai

  zone_id    = data.terraform_remote_state.africa_eks.outputs.airbyte_internal_zone_id
  vpc_id     = local.mumbai.vpc_id
  vpc_region = "ap-south-1"
}
