########################################
# Remote state (read only), prod state bucket (ap-south-1)
########################################

# Africa bootstrap: vpc_id, vpc_cidr, public/private_route_table_id, rds_sg_id
data "terraform_remote_state" "africa_bootstrap" {
  backend = "s3"

  config = {
    bucket  = "production-eks-terraform-state"
    key     = "dalgo-prod-af/bootstrap/terraform.tfstate"
    region  = "ap-south-1"
    profile = "dalgo-prod-admin"
  }
}

# Africa EKS: cluster_security_group_id (SSH rule), airbyte_internal_zone_id (manual association command)
data "terraform_remote_state" "africa_eks" {
  backend = "s3"

  config = {
    bucket  = "production-eks-terraform-state"
    key     = "dalgo-prod-af/eks/terraform.tfstate"
    region  = "ap-south-1"
    profile = "dalgo-prod-admin"
  }
}

locals {
  africa        = data.terraform_remote_state.africa_bootstrap.outputs
  africa_eks    = data.terraform_remote_state.africa_eks.outputs
  mumbai_ec2_32 = "${var.mumbai_ec2_private_ip}/32"
}

########################################
# 1. Peering REQUEST from Africa to Mumbai prod. Inter-region: the other side must accept,
#    so it stays "pending-acceptance" until someone accepts it in ap-south-1 (manual step 1).
########################################

resource "aws_vpc_peering_connection" "africa_mumbai" {
  vpc_id      = local.africa.vpc_id
  peer_vpc_id = var.mumbai_vpc_id
  peer_region = "ap-south-1"
  # peer_owner_id omitted: same account. auto_accept is not allowed inter-region.

  tags = {
    Name = "dalgo-prod-af-mumbai-peering"
    Side = "requester"
  }

  lifecycle {
    precondition {
      condition     = local.africa.vpc_cidr != var.mumbai_vpc_cidr
      error_message = "Mumbai and Africa VPC CIDRs overlap; peering needs distinct CIDRs."
    }
  }
}

########################################
# 2. Africa -> Mumbai routes. Only after the peering is active (peering_accepted = true).
#    Private: nodes, pods, internal ALB. Public: symmetry (only the NAT lives there).
#    Separate aws_route resources: the bootstrap route tables have no inline routes, so a bootstrap
#    apply never removes these.
########################################

resource "aws_route" "africa_to_mumbai" {
  for_each = var.peering_accepted ? {
    public  = local.africa.public_route_table_id
    private = local.africa.private_route_table_id
  } : {}

  route_table_id            = each.value
  destination_cidr_block    = var.mumbai_vpc_cidr # 172.31.0.0/16
  vpc_peering_connection_id = aws_vpc_peering_connection.africa_mumbai.id
}

########################################
# 3. Africa Airbyte RDS (5432) from the Mumbai prod EC2 only (jump host: ssh -L from a laptop).
#    /32, not 172.31.0.0/16: Mumbai EKS pods and everything else in Mumbai stay blocked.
#    Here (not in bootstrap) so destroying this folder removes the access with the link.
#    Safe as a separate rule: the Africa RDS SG has no inline ingress blocks.
########################################

resource "aws_vpc_security_group_ingress_rule" "rds_from_mumbai_ec2" {
  security_group_id = local.africa.rds_sg_id
  description       = "Postgres from Mumbai prod EC2 (jump host) over peering"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = local.mumbai_ec2_32

  tags = {
    Name   = "dalgo-prod-af-rds-from-mumbai-ec2"
    Subset = "airbyte"
  }
}

########################################
# 4. SSH (22) into Africa EKS nodes from the Mumbai prod EC2 only, over peering.
#    On the cluster SG, which every managed node carries. Key pair: cluster/terraform var.ssh_key_name.
#    Usage, on the Mumbai EC2: ssh -i <af key>.pem ec2-user@<africa node private IP>
########################################

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_ssh_from_mumbai_ec2" {
  security_group_id = local.africa_eks.cluster_security_group_id
  description       = "SSH from Mumbai prod EC2 (jump host) over peering"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = local.mumbai_ec2_32

  tags = {
    Name = "dalgo-prod-af-eks-ssh-from-mumbai-ec2"
  }
}

# Airbyte API needs no rule here: the Mumbai EC2 reaches it via the internal ALB, whose SG the LB
# controller builds from the Ingress inbound-cidrs annotation (Mumbai EC2 /32 + Africa VPC).
