# Staging EC2 (Prefect server box). SSH key pair is created by hand.
# Needs bootstrap/ applied first. Software on the box is installed by hand.

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  backend "s3" {
    bucket       = "test-state-and-lock-bucket-staging"
    key          = "test/staging-ec2/dalgo-staging/terraform.tfstate"
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
    bucket  = "test-state-and-lock-bucket-staging"
    key     = "test/bootstrap/dalgo-staging/terraform.tfstate"
    region  = "ap-south-1"
    profile = "dalgo-staging-admin"
  }
}

locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs
}
