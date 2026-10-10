# Dalgo staging EKS cluster (account 323443472031).
# LB controller and cluster-autoscaler are installed with helm (see cluster/ingress, cluster/autoscaler).

# State + lock live in S3 (use_lockfile needs Terraform >= 1.10; no DynamoDB).
# Different profile name? `terraform init -backend-config="profile=<yours>"`.
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
    key          = "eks/dalgo-staging-cluster/terraform.tfstate"
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
      Environment = "Staging"
      Product     = "Dalgo"
      ManagedBy   = "terraform"
    }
  }
}

locals {
  iam_prefix = "dalgo-staging-eks"
}

########################################
# IAM: cluster role
########################################

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name               = "${local.iam_prefix}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

########################################
# IAM: node role (shared by all node groups)
########################################

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node_group_role" {
  name               = "${local.iam_prefix}-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json
}

# resource "aws_iam_policy" "cloudwatch_metrics" {
#   name        = "${local.iam_prefix}-cloudwatch-metrics"
#   description = "Lets nodes push/read CloudWatch metrics"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Action = [
#         "cloudwatch:PutMetricData",
#         "cloudwatch:GetMetricData",
#         "cloudwatch:ListMetrics",
#         "ec2:DescribeVolumes",
#         "ec2:DescribeTags",
#       ]
#       Resource = "*"
#     }]
#   })
# }

# EC2FullAccess / S3FullAccess (old node roles) dropped: unused, apps get their own roles.
resource "aws_iam_role_policy_attachment" "eks_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    # "arn:aws:iam::aws:policy/AmazonEC2FullAccess", ## CHECK THIS.
    # "arn:aws:iam::aws:policy/AmazonS3FullAccess", ## unused for 400+ days on old staging
    # aws_iam_policy.cloudwatch_metrics.arn,
  ])

  role       = aws_iam_role.eks_node_group_role.name
  policy_arn = each.value
}

########################################
# EKS cluster
########################################

resource "aws_eks_cluster" "eks_cluster" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  access_config {
    # access entries only, no aws-auth ConfigMap
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    # control plane ENIs, 2+ AZs
    subnet_ids              = data.aws_subnet.cluster_subnets[*].id
    endpoint_private_access = true # in-VPC callers reach the API without NAT
    endpoint_public_access  = true # kubectl from laptops
  }

  enabled_cluster_log_types = var.cluster_log_types

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# staging EC2 -> cluster (all ports). Laptop kubectl uses the public endpoint, not this.
resource "aws_security_group_rule" "whitelist_security_group_rules" {
  count = length(var.api_whitelist_security_group_ids)

  description              = "Allow traffic from whitelisted SG (bastion / kubectl / debugging)"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = var.api_whitelist_security_group_ids[count.index]
  security_group_id        = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
}

# cluster -> Prefect server on staging EC2 (4200)
resource "aws_security_group_rule" "prefect_server_from_cluster" {
  count = var.staging_ec2_sg_id == null ? 0 : 1

  description              = "Prefect server API from EKS pods"
  type                     = "ingress"
  from_port                = 4200
  to_port                  = 4200
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  security_group_id        = var.staging_ec2_sg_id
}

# cluster -> staging RDS (5432)
resource "aws_security_group_rule" "rds_from_cluster" {
  count = var.rds_sg_id == null ? 0 : 1

  description              = "Postgres from EKS pods"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  security_group_id        = var.rds_sg_id
}

########################################
# Cluster admins (access entries)
########################################

# Extra cluster-admins (SSO role ARNs). Creator's role gets admin automatically.
## CHECK: see if we can move this out (ishan)
resource "aws_eks_access_entry" "admins" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "admins" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admins]
}

########################################
# Node groups
########################################

resource "aws_eks_node_group" "eks_node_group" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "staging-node-group-${each.key}"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = var.node_subnet_ids
  version         = var.cluster_version

  ami_type       = "AL2023_ARM_64_STANDARD" ## CHECK if we can update this
  capacity_type  = "ON_DEMAND"
  instance_types = each.value.instance_types
  disk_size      = each.value.disk_size
  labels         = each.value.labels

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  dynamic "remote_access" {
    for_each = var.ssh_key_name == null ? [] : [1]
    content {
      ec2_ssh_key = var.ssh_key_name
      # SSH only from these SGs (else EKS opens 22 to the VPC)
      source_security_group_ids = var.api_whitelist_security_group_ids
    }
  }

  # autoscaler owns desired_size
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_node_policies]
}

# EC2 Name/Subset tags via the node groups' ASGs (node group tags don't reach EC2s).
# Nodes launched before these tags exist stay untagged until replaced.
locals {
  node_ec2_tags = merge([
    for ng_key, ng in var.node_groups : {
      for tag_key, tag_value in {
        Name        = "dalgo-${lower(ng.subset)}-staging-eks-node"
        Product     = "Dalgo"
        Environment = "Staging"
        Subset      = ng.subset
      } : "${ng_key}/${tag_key}" => { node_group = ng_key, key = tag_key, value = tag_value }
    }
  ]...)
}

resource "aws_autoscaling_group_tag" "node_ec2_tags" {
  for_each = local.node_ec2_tags

  autoscaling_group_name = aws_eks_node_group.eks_node_group[each.value.node_group].resources[0].autoscaling_groups[0].name

  tag {
    key                 = each.value.key
    value               = each.value.value
    propagate_at_launch = true
  }
}

########################################
# Managed add-ons
########################################

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# gives pods their Pod Identity credentials
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.eks_node_group]
}

# for HPAs and `kubectl top`
resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.eks_node_group]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # start after Pod Identity is ready, so the controller gets credentials
  depends_on = [
    aws_eks_node_group.eks_node_group,
    aws_eks_addon.pod_identity_agent,
    aws_eks_pod_identity_association.pod_roles,
  ]
}

########################################
# Pod roles (EKS Pod Identity)
# Each role is linked to one kube-system service account (created by the add-on/helm).
# Service account names must match exactly.
########################################

data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

locals {
  pod_role_service_accounts = {
    ebs_csi            = "ebs-csi-controller-sa"
    cluster_autoscaler = "cluster-autoscaler"
    lb_controller      = "aws-load-balancer-controller"
  }

  pod_role_arns = {
    ebs_csi            = aws_iam_role.ebs_csi.arn
    cluster_autoscaler = aws_iam_role.cluster_autoscaler.arn
    lb_controller      = aws_iam_role.lb_controller.arn
  }
}

resource "aws_eks_pod_identity_association" "pod_roles" {
  for_each = local.pod_role_service_accounts

  cluster_name    = aws_eks_cluster.eks_cluster.name
  namespace       = "kube-system"
  service_account = each.value
  role_arn        = local.pod_role_arns[each.key]
}

# EBS CSI driver
resource "aws_iam_role" "ebs_csi" {
  name               = "${local.iam_prefix}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Cluster autoscaler
resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${local.iam_prefix}-cluster-autoscaler"
  description = "Permissions for cluster-autoscaler to scale EKS managed node groups"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "autoscaling:DescribeScalingActivities",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:GetInstanceTypesFromInstanceRequirements",
        "eks:DescribeNodegroup",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${local.iam_prefix}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

# AWS load balancer controller. Policy = upstream v2.13 iam_policy.json (update on upgrades)
resource "aws_iam_policy" "lb_controller" {
  name        = "${local.iam_prefix}-aws-load-balancer-controller"
  description = "Permissions for aws-load-balancer-controller"
  policy      = file("${path.module}/aws_load_balancer_controller_iam_policy.json")
}

resource "aws_iam_role" "lb_controller" {
  name               = "${local.iam_prefix}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

########################################
# Outputs
########################################

output "cluster_name" {
  value = aws_eks_cluster.eks_cluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "cluster_security_group_id" {
  description = "Cluster SG (control plane + nodes)"
  value       = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
}

output "cluster_autoscaler_role_arn" {
  value = aws_iam_role.cluster_autoscaler.arn
}

output "lb_controller_role_arn" {
  value = aws_iam_role.lb_controller.arn
}

output "node_group_role_arn" {
  value = aws_iam_role.eks_node_group_role.arn
}

output "vpc_id" {
  description = "For the LB controller helm install"
  value       = data.aws_vpc.current_vpc.id
}

output "acm_certificate_arn" {
  description = "For alb.ingress.kubernetes.io/certificate-arn"
  value       = aws_acm_certificate.wildcard.arn
}

output "acm_validation_records" {
  description = "Add in Cloudflare (DNS only)"
  value = [for o in aws_acm_certificate.wildcard.domain_validation_options : {
    name  = o.resource_record_name
    type  = o.resource_record_type
    value = o.resource_record_value
  }]
}

output "airbyte_internal_zone_id" {
  description = "Private zone; add an alias A record to the internal ALB"
  value       = aws_route53_zone.airbyte_internal.zone_id
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.eks_cluster.name} --region ${var.aws_region} --profile ${var.aws_profile}"
}
