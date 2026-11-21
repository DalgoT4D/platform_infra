# Africa prod <-> Mumbai prod VPC peering: AFRICA SIDE ONLY.
#
# Mumbai prod (vpc-060665f96234a5997) is not managed by terraform, and this folder never writes to it:
# there is only an af-south-1 provider. The Mumbai half (accept the request, route, SG rule, private zone
# association, ufw) is done by hand; `terraform output mumbai_manual_steps` prints the exact commands.
#
# Two applies:
#   1. peering_accepted = false: creates the peering request + Africa SG rules. Then do the Mumbai steps.
#   2. peering_accepted = true:  adds the Africa -> Mumbai routes (needs an active peering).
# Apply after ../bootstrap and ../cluster/terraform (reads both states).

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  # NEW key, owned by this folder only.
  backend "s3" {
    bucket       = "production-eks-terraform-state"
    key          = "dalgo-prod-af/peering/terraform.tfstate"
    region       = "ap-south-1" # state bucket region
    profile      = "dalgo-prod-admin"
    encrypt      = true
    use_lockfile = true
  }
}

# Africa only. Deliberately NO ap-south-1 provider: nothing here can change Mumbai prod.
provider "aws" {
  region  = "af-south-1"
  profile = var.aws_profile

  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Product     = "dalgo"
      Environment = "production"
      Region      = "af-south-1"
      Subset      = "shared"
      ManagedBy   = "terraform"
    }
  }
}
