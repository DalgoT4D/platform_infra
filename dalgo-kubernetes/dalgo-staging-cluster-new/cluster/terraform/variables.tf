variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile pointing at the new staging account"
  type        = string
}

variable "aws_account_id" {
  description = "New staging AWS account ID (provider refuses to run against any other)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "dalgo-staging-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for control plane and node groups"
  type        = string
  default     = "1.36"
}

variable "vpc_id" {
  description = "The existing VPC ID in the new account"
  type        = string
}

variable "cluster_subnet_ids" {
  description = "Subnets for the EKS control plane ENIs (min 2, in different AZs). Use the private subnets."
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Private subnet(s) where worker nodes run. Single AZ keeps EBS volumes and pods together."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnets in at least 2 AZs. Tagged kubernetes.io/role/elb=1 for internet-facing ALBs."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets in at least 2 AZs. Tagged kubernetes.io/role/internal-elb=1 for internal ALBs."
  type        = list(string)
}

variable "acm_domain" {
  description = "Domain for the ACM certificate used by the ALB ingresses"
  type        = string
  default     = "*.dalgo.org"
}

variable "airbyte_internal_domain" {
  description = "Hostname of the internal airbyte ALB (private hosted zone)"
  type        = string
  default     = "airbyte-staging-internal.dalgo.org"
}

variable "cluster_log_types" {
  description = "Control plane log types sent to CloudWatch. Empty = disabled (current staging setting)."
  type        = list(string)
  default     = []
}

variable "admin_principal_arns" {
  description = "IAM user/role ARNs that get cluster-admin via EKS access entries (e.g. SSO admin role). Do NOT include the identity running terraform: it already gets admin via bootstrap_cluster_creator_admin_permissions, and a duplicate entry fails the apply."
  type        = list(string)
  default     = []
}

variable "api_whitelist_security_group_ids" {
  description = "Security groups (e.g. bastion / EC2 machines) allowed to reach the cluster API and nodes"
  type        = list(string)
  default     = []
}

variable "staging_ec2_sg_id" {
  description = "SG of the staging EC2 (Prefect server). Terraform adds one rule to it: 4200 from the cluster SG. null = skip."
  type        = string
  default     = null
}

variable "rds_sg_id" {
  description = "SG of the staging RDS. Terraform adds one rule to it: 5432 from the cluster SG. null = skip (until RDS exists)."
  type        = string
  default     = null
}

variable "ssh_key_name" {
  description = "EC2 key pair for SSH into nodes. Must exist in the new account. null = no SSH."
  type        = string
  default     = null
}

variable "node_groups" {
  description = "Managed node groups keyed by name suffix"
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    subset         = string # Subset tag; also gives the EC2 Name: dalgo-<subset>-staging-eks-node
    disk_size      = optional(number, 20)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string # NO_SCHEDULE | NO_EXECUTE | PREFER_NO_SCHEDULE
    })), [])
  }))

  # Mirrors node groups on the old staging cluster
  default = {
    "static-control" = {
      subset         = "Airbyte"
      instance_types = ["t4g.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      labels         = { type = "static" }
    }
    "dynamic" = {
      subset         = "Airbyte"
      instance_types = ["t4g.large"]
      min_size       = 1
      max_size       = 4
      desired_size   = 1
      labels         = { type = "jobs" }
    }
    "prefect-worker" = {
      subset         = "Prefect"
      instance_types = ["t4g.medium"]
      min_size       = 1
      max_size       = 4
      desired_size   = 1
      labels         = { type = "prefect-worker" }
    }
    "supersets" = {
      subset         = "Superset"
      instance_types = ["t4g.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      disk_size      = 50
      labels         = { workload = "superset" }                                           ## CHECK this, can we make it type.  
      taints         = [{ key = "dedicated", value = "superset", effect = "NO_SCHEDULE" }] # if we have lables then why we need taint ? 
    }
  }
}
