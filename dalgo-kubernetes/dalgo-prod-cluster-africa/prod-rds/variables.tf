# Defaults below apply unless set in terraform.tfvars. Any variable here can be overridden there (e.g. availability_zone = "af-south-1b").

########################################
# Account
########################################

variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "af-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile pointing at the prod account (024209611402)"
  type        = string
}

variable "aws_account_id" {
  description = "Prod AWS account ID (provider refuses to run against any other)"
  type        = string
}

########################################
# Instance (Airbyte only; same class as Mumbai prod airbyte-prod-2)
########################################

variable "identifier" {
  description = "RDS instance identifier (also the endpoint hostname prefix)"
  type        = string
  default     = "dalgo-prod-af-airbyte-rds"
}

# Major only: minor versions are upgraded by AWS (auto_minor_version_upgrade).
# Check af-south-1 offers it: aws rds describe-db-engine-versions --engine postgres --region af-south-1
variable "engine_version" {
  description = "Postgres major version"
  type        = string
  default     = "18"
}

variable "instance_class" {
  description = "Instance class (db.t4g.small = Graviton, ~10% cheaper)"
  type        = string
  default     = "db.t3.small"
}

variable "allocated_storage" {
  description = "Storage in GiB (gp3)."
  type        = number
  default     = 50
}

variable "availability_zone" {
  description = "AZ of the instance. Same as the EKS nodes keeps traffic in one AZ."
  type        = string
  default     = "af-south-1a"
}

variable "master_username" {
  description = "Master user"
  type        = string
  default     = "postgres"
}

# Set in terraform.tfvars (gitignored). Store it in the team vault. NOT the Mumbai prod or staging Africa password.
variable "master_password" {
  description = "Master user password (min 8 chars; no / \" @ or spaces)"
  type        = string
  sensitive   = true
  ephemeral   = true # never written to state or plan files
}

variable "master_password_version" {
  description = "Bump (1 -> 2 -> ...) to push a changed master_password to RDS"
  type        = number
  default     = 1
}

variable "snapshot_identifier" {
  description = "Snapshot to restore from (name or ARN, must be in af-south-1). null = new empty DB."
  type        = string
  default     = null
}

variable "max_connections" {
  description = "max_connections parameter (applied on reboot)"
  type        = number
  default     = 300
}

variable "backup_retention_days" {
  description = "Automated backup retention"
  type        = number
  default     = 7
}
