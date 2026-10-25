# Account bootstrap: VPC, subnets, IGW, NAT, route tables, security groups.
# Apply first. staging-ec2/, staging-rds/ and cluster/terraform read from it.

# State + lock in S3. Bucket must exist first (created by hand).
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
    key          = "dalgo-staging/bootstrap/terraform.tfstate"
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

  # Subset: shared (network is used by airbyte, prefect, superset and monitoring)
  default_tags {
    tags = {
      Product     = "dalgo"
      Environment = "staging"
      Subset      = "shared"
      ManagedBy   = "terraform"
    }
  }
}
