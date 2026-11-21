# Africa (af-south-1) account bootstrap: VPC, subnets, IGW, NAT, route tables, S3 endpoint, ECR cache, RDS SG.
# Copy of dalgo-staging-cluster/bootstrap, edited for Africa. Apply first: staging-rds/, cluster/terraform
# and peering/ read from it.

# Same state bucket as Mumbai (it lives in ap-south-1), but a NEW key. Never reuse a Mumbai key:
# that would point this folder at Mumbai's state and plan to destroy Mumbai.
terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  backend "s3" {
    bucket       = "terraform-state-and-lock-bucket"
    key          = "dalgo-staging-af/bootstrap/terraform.tfstate"
    region       = "ap-south-1" # region of the state bucket, not of the resources
    profile      = "dalgo-staging-admin"
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
      Environment = "staging"
      Region      = "af-south-1"
      Subset      = "shared"
      ManagedBy   = "terraform"
    }
  }
}
