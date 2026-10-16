# Account bootstrap: VPC, subnets, IGW, NAT, route tables, security groups.
# Apply first. staging-ec2/ and cluster/terraform read from it.

# State + lock in S3. Bucket must exist first (new account: create it by hand or in a later state stack).
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
    key          = "test/bootstrap/dalgo-staging/terraform.tfstate"
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
