# define all config vars that will reference tfvars
variable "aws_region" {
  description = "The AWS region"
  type        = string
}

variable "aws_profile" {
  description = "The AWS profile"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "The list of subnet IDs"
  type        = list(string)
}

variable "iam_cluster_role" {
  description = "The IAM role for the EKS cluster"
  type        = string
}

variable "whitelist_security_group_ids" {
  description = "The list of security group IDs to whitelist"
  type        = list(string)
}

variable "iam_node_group_role" {
  description = "The IAM role for the EKS node group"
  type        = string
}

# configure the AWS provider
provider "aws" {
  region = var.aws_region
  profile = var.aws_profile
}

# S3 Bucket for State - ensure it exists
data "aws_s3_bucket" "terraform_state" {
  bucket = "staging-superset-eks-tf-state"
}

# DynamoDB for State Locking - ensure it exists
data "aws_dynamodb_table" "terraform_locks" {
  name         = "staging-superset-eks-tf-state-locks"
}

# Terraform Backend Configuration
terraform {
  backend "s3" {
    bucket         = "staging-superset-eks-tf-state"
    key            = "global/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "staging-superset-eks-tf-state-locks"
    encrypt        = true
  }
}

# data resources to reference existing VPC and subnets
data "aws_vpc" "current_vpc" {
  id = var.vpc_id
}

data "aws_subnet" "curr_vpc_subnets" {
  count = length(var.subnet_ids)
  id    = element(var.subnet_ids, count.index)
}


data "aws_iam_role" "iam_cluster_role" {
  name = var.iam_cluster_role
}

# create eks cluster and kubernetes provider
resource "aws_eks_cluster" "eks_cluster" {
  name     = "dalgo-superset-staging-cluster"
  role_arn = data.aws_iam_role.iam_cluster_role.arn
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access = true
    subnet_ids = data.aws_subnet.curr_vpc_subnets[*].id
  }

  tags = {
    Environment = "Staging"
    Product     = "Dalgo"
  }

  enabled_cluster_log_types = ["audit", "api", "authenticator", "scheduler", "controllerManager"]
}

# cluster security group
resource "aws_security_group" "eks_cluster_sg" {
  name        = "dalgo-superset-staging-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = data.aws_vpc.current_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dalgo-superset-staging-cluster-sg"
  }
}

# node security group
resource "aws_security_group" "eks_nodes_sg" {
  name        = "dalgo-superset-staging-nodes-sg"
  description = "Security group for worker nodes"
  vpc_id      = data.aws_vpc.current_vpc.id

  tags = {
    Name                                          = "dalgo-superset-staging-nodes-sg"
    "kubernetes.io/cluster/dalgo-superset-staging-cluster"    = "owned"
  }
}


# Allow https traffice from bastion host in the vpc for running kubectl commands
resource "aws_security_group_rule" "whitelist_security_group_rules" {
  count = length(var.whitelist_security_group_ids)

  description       = "Allow https traffic from bastion host to connect to cluster for running/debugging with kubectl"
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  source_security_group_id = var.whitelist_security_group_ids[count.index]
  security_group_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
}

# Allow inbound traffic from the cluster security group
resource "aws_security_group_rule" "nodes_inbound_cluster" {
  description              = "Allow worker nodes to receive communication from the cluster control plane"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_cluster_sg.id
  security_group_id        = aws_security_group.eks_nodes_sg.id
}


# Allow all outbound traffic
resource "aws_security_group_rule" "nodes_outbound_sg" {
  description       = "Allow all outbound traffic from nodes"
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  security_group_id = aws_security_group.eks_nodes_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}


# Allow nodes to communicate with each other
resource "aws_security_group_rule" "nodes_internal_sg" {
  description              = "Allow nodes to communicate with each other"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_nodes_sg.id
  security_group_id        = aws_security_group.eks_nodes_sg.id
}


# Allow worker nodes to access the cluster API Server
resource "aws_security_group_rule" "cluster_inbound" {
  description              = "Allow worker nodes to communicate with the cluster API Server"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes_sg.id
  security_group_id        = aws_security_group.eks_cluster_sg.id
}


# Common ports needed for worker nodes
resource "aws_security_group_rule" "nodes_kubelet" {
  description       = "Allow kubelet API"
  type              = "ingress"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes_sg.id
  cidr_blocks       = [data.aws_vpc.current_vpc.cidr_block]
}


resource "aws_security_group_rule" "nodes_kubeproxy" {
  description       = "Allow kube-proxy"
  type              = "ingress"
  from_port         = 10256
  to_port           = 10256
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes_sg.id
  cidr_blocks       = [data.aws_vpc.current_vpc.cidr_block]
}

resource "aws_security_group_rule" "nodes_nodeports" {
  description       = "Allow NodePort Services"
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}



provider "kubernetes" {
  host                   = aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.eks_cluster.name, "--region", var.aws_region]
    command     = "aws"
  }
}

# data resources to reference existing iam roles
data "aws_iam_role" "eks_node_group_role" {
  name = var.iam_node_group_role
} 

# create the autoscaler role and attach policies/trust relationships
data "tls_certificate" "eks" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "eks_cluster_autoscaler_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "eks_cluster_autoscaler_role" {
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_autoscaler_assume_role_policy.json
  name               = "eks-superset-cluster-autoscaler-staging"
}

resource "aws_iam_role_policy_attachment" "attach_eks_cluster_autoscaler_policy" {
  role       = aws_iam_role.eks_cluster_autoscaler_role.name
  policy_arn = "arn:aws:iam::024209611402:policy/eks-cluster-autoscaler" # customer managed policy
}


# create node group and its instances
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "eks-superset-staging-node-group"
  node_role_arn   = data.aws_iam_role.eks_node_group_role.arn
  subnet_ids      = var.subnet_ids
  instance_types  = ["t4g.large"]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 5
  }

  # This AMI type matches current AMI deployed on production. Might be useful to compare other 
  # performant instance type
  ami_type = "AL2023_ARM_64_STANDARD"


  # Add the security group to the node group
  remote_access {
    ec2_ssh_key = "dalgo-eks-ec2-key-pair" # Optional: Replace with your SSH key pair name if needed
  }

  tags = {
    Environment = "Staging"
    Product     = "Dalgo"
    "k8s.io/cluster-autoscaler/enabled" = "true"
    "k8s.io/cluster-autoscaler/dalgo-superset-staging-cluster" = "owned"
  }

}

# cluster autoscaler
resource "kubernetes_service_account" "kube_service_acc_user" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.eks_cluster_autoscaler_role.arn
    }
  }
}

resource "kubernetes_cluster_role" "kube_cluster_autoscaler_role" {
  metadata {
    name = "cluster-autoscaler"
  }

  rule {
    api_groups = [""]
    resources  = ["events", "endpoints"]
    verbs      = ["create", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/eviction"]
    verbs      = ["create"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/status"]
    verbs      = ["update"]
  }

  rule {
    api_groups     = [""]
    resources      = ["endpoints"]
    resource_names = ["cluster-autoscaler"]
    verbs          = ["get", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["watch", "list", "get", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "services", "replicationcontrollers", "persistentvolumeclaims", "persistentvolumes"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["replicasets", "daemonsets"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["watch", "list"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets", "replicasets", "daemonsets"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses", "csinodes", "csidrivers", "csistoragecapacities"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["batch", "extensions"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch", "patch"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["create"]
  }

  rule {
    api_groups     = ["coordination.k8s.io"]
    resource_names = ["cluster-autoscaler"]
    resources      = ["leases"]
    verbs          = ["get", "update"]
  }
}

resource "kubernetes_cluster_role_binding" "kube_cluster_autoscaler_role_binding" {
  metadata {
    name = "cluster-autoscaler"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.kube_cluster_autoscaler_role.metadata.0.name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.kube_service_acc_user.metadata.0.name
    namespace = kubernetes_service_account.kube_service_acc_user.metadata.0.namespace
  }
}

resource "kubernetes_deployment" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    labels = {
      app = "cluster-autoscaler"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "cluster-autoscaler"
      }
    }

    template {
      metadata {
        labels = {
          app = "cluster-autoscaler"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.kube_service_acc_user.metadata.0.name

        container {
          name  = "cluster-autoscaler"
          image = "k8s.gcr.io/autoscaling/cluster-autoscaler:v1.27.3"

          command = [
            "./cluster-autoscaler",
            "--v=4",
            "--stderrthreshold=info",
            "--cloud-provider=aws",
            "--skip-nodes-with-local-storage=false",
            "--expander=least-waste",
            "--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/dalgo-superset-staging-cluster"
          ]

          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "500Mi" # Increase the memory request
            }
            limits = {
              cpu    = "200m" # Increase the CPU limit
              memory = "1Gi"  # Increase the memory limit
            }
          }
        }
      }
    }
  }
}