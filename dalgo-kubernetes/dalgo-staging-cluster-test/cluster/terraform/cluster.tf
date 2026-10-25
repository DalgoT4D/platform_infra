# Dalgo staging EKS cluster (account 323443472031).
# LB controller and cluster-autoscaler are installed with helm (see cluster/ingress, cluster/autoscaler).

# State + lock in S3. Other profile: terraform init -backend-config="profile=<yours>"
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
    key          = "dalgo-staging/eks/terraform.tfstate"
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

  # Subset: shared by default (cluster, IAM, add-ons serve every app); node groups and the
  # airbyte zone override it. default_tags don't reach node EC2s: see node_ec2_tags below.
  default_tags {
    tags = {
      Product     = "dalgo"
      Environment = "staging"
      Subset      = "shared"
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

  tags = {
    Name = "${local.iam_prefix}-cluster-role"
  }
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

  tags = {
    Name = "${local.iam_prefix}-node-role"
  }
}


# EC2FullAccess / S3FullAccess (old node roles) dropped: unused, apps get their own roles.
resource "aws_iam_role_policy_attachment" "eks_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
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
    subnet_ids              = local.cluster_subnet_ids
    endpoint_private_access = true # in-VPC callers reach the API without NAT, control plane enis are in private subnet. 
    endpoint_public_access  = true # kubectl from laptops
  }

  enabled_cluster_log_types = var.cluster_log_types

  tags = {
    Name = var.cluster_name
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# staging EC2 -> cluster (all ports) on private end points. Laptop kubectl uses the public endpoint, not this.
# staging amchine can direclty talk to cluster without traffic going outside the vpc. 
resource "aws_vpc_security_group_ingress_rule" "whitelist_security_group_rules" {
  description                  = "Allow traffic from the staging EC2 SG (kubectl / debugging)"
  ip_protocol                  = "-1"
  referenced_security_group_id = local.staging_ec2_sg_id
  security_group_id            = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id

  tags = {
    Name = "${var.cluster_name}-from-staging-ec2"
  }
}

# cluster -> Prefect server on staging EC2 (4200)
resource "aws_vpc_security_group_ingress_rule" "prefect_server_from_cluster" {
  description                  = "Prefect server API from EKS pods"
  ip_protocol                  = "tcp"
  from_port                    = 4200
  to_port                      = 4200
  referenced_security_group_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  security_group_id            = local.staging_ec2_sg_id

  tags = {
    Name   = "${var.cluster_name}-to-prefect-server"
    Subset = "prefect"
  }
}

# cluster -> staging RDS (5432)
resource "aws_vpc_security_group_ingress_rule" "rds_from_cluster" {
  description                  = "Postgres from EKS pods"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  security_group_id            = local.rds_sg_id

  tags = {
    Name = "${var.cluster_name}-to-rds"
  }
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

  tags = {
    Name = "${var.cluster_name}-admin-${element(split("/", each.value), length(split("/", each.value)) - 1)}"
  }
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
  node_group_name = "dalgo-staging-node-group-${each.key}"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = local.node_subnet_ids
  version         = var.cluster_version
  release_version = var.node_ami_release_version

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
      source_security_group_ids = [local.staging_ec2_sg_id]
    }
  }

  tags = {
    Name   = "dalgo-staging-node-group-${each.key}"
    Subset = each.value.subset
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
        Name        = "dalgo-staging-${ng.subset}-eks-node"
        Product     = "dalgo"
        Environment = "staging"
        Subset      = ng.subset
        ManagedBy   = "terraform"
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
# Versions: var.addon_versions. Uninstall = delete block + apply.

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "vpc-cni"
  addon_version               = var.addon_versions["vpc-cni"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.cluster_name}-vpc-cni"
  }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "kube-proxy"
  addon_version               = var.addon_versions["kube-proxy"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.cluster_name}-kube-proxy"
  }
}

# gives pods their Pod Identity credentials
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = var.addon_versions["eks-pod-identity-agent"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.cluster_name}-eks-pod-identity-agent"
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "coredns"
  addon_version               = var.addon_versions["coredns"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.cluster_name}-coredns"
  }

  depends_on = [aws_eks_node_group.eks_node_group]
}

# for HPAs and `kubectl top`
resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "metrics-server"
  addon_version               = var.addon_versions["metrics-server"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.cluster_name}-metrics-server"
  }

  depends_on = [aws_eks_node_group.eks_node_group]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.addon_versions["aws-ebs-csi-driver"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.cluster_name}-aws-ebs-csi-driver"
  }

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

  tags = {
    Name = "${var.cluster_name}-${each.value}"
  }
}

# EBS CSI driver
resource "aws_iam_role" "ebs_csi" {
  name               = "${local.iam_prefix}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json

  tags = {
    Name = "${local.iam_prefix}-ebs-csi-driver"
  }
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

  tags = {
    Name = "${local.iam_prefix}-cluster-autoscaler"
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${local.iam_prefix}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json

  tags = {
    Name = "${local.iam_prefix}-cluster-autoscaler"
  }
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

  tags = {
    Name = "${local.iam_prefix}-aws-load-balancer-controller"
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${local.iam_prefix}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json

  tags = {
    Name = "${local.iam_prefix}-aws-load-balancer-controller"
  }
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
  value       = local.vpc_id
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
