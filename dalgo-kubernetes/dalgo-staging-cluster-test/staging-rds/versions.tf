# Staging RDS (Postgres) + its subnet group and parameter group. Master password: fixed, from tfvars.
# Needs bootstrap/ applied first. Holds data: deletion protection is on.

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  backend "s3" {
    bucket       = "test-terraform-state-and-lock-bucket"
    key          = "test/staging-rds/dalgo-staging/terraform.tfstate"
    region       = "ap-south-1"
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

  default_tags {
    tags = {
      Environment = "test-staging"
      Product     = "Dalgo"
      ManagedBy   = "terraform"
    }
  }
}

# VPC, subnet and SG IDs from bootstrap/
data "terraform_remote_state" "bootstrap" {
  backend = "s3"

  config = {
    bucket  = "test-terraform-state-and-lock-bucket"
    key     = "test/bootstrap/dalgo-staging/terraform.tfstate"
    region  = "ap-south-1"
    profile = "dalgo-staging-admin"
  }
}

locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs
}
