# Mumbai <-> Africa VPC peering, routes on both sides, the Prefect 4200 SG rule on the Mumbai EC2, and
# the 5432 rule on the Africa RDS SG for the Mumbai EC2 (jump host).
# Apply after: Mumbai bootstrap (with the route-table outputs + aws_route conversion) and Africa bootstrap.
# Destroying this folder removes only the Mumbai<->Africa link; nothing else in Mumbai.

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
    bucket       = "terraform-state-and-lock-bucket"
    key          = "dalgo-staging-af/peering/terraform.tfstate"
    region       = "ap-south-1" # state bucket region
    profile      = "dalgo-staging-admin"
    encrypt      = true
    use_lockfile = true
  }
}

# Requester side: Mumbai. Legitimately ap-south-1 (Mumbai VPC, route tables, EC2 SG).
provider "aws" {
  alias   = "mumbai"
  region  = "ap-south-1"
  profile = var.aws_profile

  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Product     = "dalgo"
      Environment = "staging"
      Subset      = "shared"
      ManagedBy   = "terraform"
    }
  }
}

# Accepter side: Africa.
provider "aws" {
  alias   = "africa"
  region  = "af-south-1"
  profile = var.aws_profile

  allowed_account_ids = [var.aws_account_id]

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
