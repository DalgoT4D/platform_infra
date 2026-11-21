# PROD Africa (af-south-1) bootstrap: VPC, subnets, IGW, NAT, route tables, S3 endpoint, ECR cache, RDS SG.
# Copy of dalgo-staging-cluster-africa/bootstrap with prod values. Apply first: prod-rds/, cluster/terraform
# and peering/ read from it.
#
# Mumbai prod (vpc-060665f96234a5997) is NOT managed by terraform, and no folder here writes to it.
# Mumbai-side peering changes are manual (../README.md).

# Prod state bucket (prod account, ap-south-1), NEW key under dalgo-prod-af/.
# Never reuse global/terraform.tfstate (old eksctl state of the Mumbai prod cluster).
# Other profile: terraform init -backend-config="profile=<yours>"
terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  backend "s3" {
    bucket       = "production-eks-terraform-state"
    key          = "dalgo-prod-af/bootstrap/terraform.tfstate"
    region       = "ap-south-1" # region of the state bucket, not of the resources
    profile      = "dalgo-prod-admin"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # refuse to run against any other account
  allowed_account_ids = [var.aws_account_id]

  # Subset: shared (network is used by airbyte and prefect)
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
