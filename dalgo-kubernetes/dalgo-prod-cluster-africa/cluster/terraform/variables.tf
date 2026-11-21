# Defaults below apply unless set in terraform.tfvars. Any variable here can be overridden there (e.g. node_subnet_azs = ["af-south-1b"]).

########################################
# Versions (Terraform + AWS provider versions: cluster.tf)
########################################

variable "cluster_version" {
  description = "Kubernetes version for control plane and node groups"
  type        = string
  default     = "1.36"
}

# Change = rolling replace of all nodes. Same as Mumbai; check it exists in af-south-1. Latest: SSM param
# /aws/service/eks/optimized-ami/<cluster_version>/amazon-linux-2023/arm64/standard/recommended/release_version
variable "node_ami_release_version" {
  description = "Node AMI release (all node groups)"
  type        = string
  default     = "1.36.4-20261003"
}

# Same as Mumbai; check each exists in af-south-1 (--region af-south-1). Latest: aws eks describe-addon-versions --kubernetes-version <v> --addon-name <name>
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

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "dalgo-prod-af-cluster"
}

# VPC and subnet IDs come from the Africa ../../bootstrap state (network.tf). Only the AZ choices live here.

variable "cluster_subnet_azs" {
  description = "AZs of the private subnets for the EKS control plane ENIs (min 2, different AZs). 1b is only for availability."
  type        = list(string)
  default     = ["af-south-1a", "af-south-1b"]
}

variable "node_subnet_azs" {
  description = "AZ(s) of the private subnet(s) where worker nodes run. One AZ (same as RDS, NAT): no cross-AZ data transfer, EBS volumes and pods stay together."
  type        = list(string)
  default     = ["af-south-1a"]
}

variable "cluster_log_types" {
  description = "Control plane log types sent to CloudWatch. Empty = disabled (same as staging Africa)."
  type        = list(string)
  default     = []
}

variable "admin_principal_arns" {
  description = "IAM user/role ARNs that get cluster-admin via EKS access entries (e.g. SSO admin role). Do NOT include the identity running terraform: it already gets admin via bootstrap_cluster_creator_admin_permissions, and a duplicate entry fails the apply."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.admin_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:(role|user)/", a))])
    error_message = "admin_principal_arns must hold full IAM role/user ARNs. Use [] for none (not [\"\"])."
  }
}

variable "peer_vpc_cidrs" {
  description = "Peered VPC CIDRs (Mumbai) the VPC CNI must not SNAT (AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS)"
  type        = list(string)
  default     = ["172.31.0.0/16"]
}

variable "acm_domain" {
  description = "Domain for the ACM certificate used by the ALB ingresses (af-south-1 cert)"
  type        = string
  default     = "*.dalgo.org"
}

variable "airbyte_internal_domain" {
  description = "Hostname of the Africa internal airbyte ALB (private hosted zone, also associated with the Mumbai VPC)"
  type        = string
  default     = "airbyte-prod-af-internal.dalgo.org"
}

variable "ssh_key_name" {
  description = "EC2 key pair (in af-south-1) for SSH into nodes from the Mumbai prod EC2 (dalgo-production-arm) over peering. Create it in the console first. null = no SSH."
  type        = string
  default     = "dalgo-prod-af-eks-rsa-key-pair"
}

variable "node_groups" {
  description = "Managed node groups keyed by name suffix"
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    subset         = string               # Subset tag (airbyte | prefect); also gives the EC2 Name: dalgo-prod-af-<subset>-eks-node
    disk_size      = optional(number, 30) # Mumbai prod node groups use 30
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string # NO_SCHEDULE | NO_EXECUTE | PREFER_NO_SCHEDULE
    })), [])
  }))

  # Same as staging Africa. Mumbai prod is bigger (t4g.xlarge / c8g.2xlarge): raise here if Africa load needs it
  # (and check the af-south-1 vCPU quota, cluster/autoscaler/cluster-autoscaler.md).
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
  }
}

########################################
# ECR pull-through cache (cache rule lives in bootstrap/ecr.tf)
########################################

variable "ecr_docker_hub_prefix" {
  description = "ECR repo prefix of the Docker Hub cache; must match bootstrap's ecr_docker_hub_prefix"
  type        = string
  default     = "docker-hub"
}
