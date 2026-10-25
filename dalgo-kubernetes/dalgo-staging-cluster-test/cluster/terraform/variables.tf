# Defaults below apply unless set in terraform.tfvars. Any variable here can be overridden there (e.g. node_subnet_azs = ["ap-south-1b"]).

########################################
# Versions (Terraform + AWS provider versions: cluster.tf)
########################################

variable "cluster_version" {
  description = "Kubernetes version for control plane and node groups"
  type        = string
  default     = "1.36"
}

# Change = rolling replace of all nodes. Latest: SSM param
# /aws/service/eks/optimized-ami/<cluster_version>/amazon-linux-2023/arm64/standard/recommended/release_version
variable "node_ami_release_version" {
  description = "Node AMI release (all node groups)"
  type        = string
  default     = "1.36.4-20261003"
}

# Bump with cluster_version. Latest: aws eks describe-addon-versions --kubernetes-version <v> --addon-name <name>
variable "addon_versions" {
  description = "EKS managed add-on versions"
  type        = map(string)
  default = {
    "vpc-cni"                = "v1.23.2-eksbuild.1"
    "kube-proxy"             = "v1.36.0-eksbuild.45"
    "eks-pod-identity-agent" = "v1.4.0-eksbuild.3"
    "coredns"                = "v1.14.7-eksbuild.11"
    "metrics-server"         = "v0.9.0-eksbuild.11"
    "aws-ebs-csi-driver"     = "v1.66.0-eksbuild.1"
  }
}

########################################
# Account, network, access
########################################

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

# VPC, subnet and SG IDs come from ../../bootstrap state (network.tf). Only the AZ choices live here.

variable "cluster_subnet_azs" {
  description = "AZs of the private subnets for the EKS control plane ENIs (min 2, different AZs). 1b is only for availability."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "node_subnet_azs" {
  description = "AZ(s) of the private subnet(s) where worker nodes run. One AZ (same as EC2, RDS, NAT): no cross-AZ data transfer, EBS volumes and pods stay together."
  type        = list(string)
  default     = ["ap-south-1a"]
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
    subset         = string # Subset tag (airbyte | prefect | superset | monitoring); also gives the EC2 Name: dalgo-staging-<subset>-eks-node
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
      subset         = "airbyte"
      instance_types = ["t4g.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      labels         = { type = "static" }
    }
    "dynamic" = {
      subset         = "airbyte"
      instance_types = ["t4g.large"]
      min_size       = 1
      max_size       = 4
      desired_size   = 1
      labels         = { type = "jobs" }
    }
    "prefect-worker" = {
      subset         = "prefect"
      instance_types = ["t4g.medium"]
      min_size       = 1
      max_size       = 4
      desired_size   = 1
      labels         = { type = "prefect-worker" }
    }
    "supersets" = {
      subset         = "superset"
      instance_types = ["t4g.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      disk_size      = 50
      labels         = { type = "superset" }
      # label pulls Superset pods here; taint keeps every other pod off these nodes
      taints = [{ key = "dedicated", value = "superset", effect = "NO_SCHEDULE" }]
    }
  }
}
