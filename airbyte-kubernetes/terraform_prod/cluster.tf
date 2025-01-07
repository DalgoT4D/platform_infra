# define all config vars that will reference tfvars
variable "vpc_id" {
  description = "The ID of the existing VPC"
  type        = string
}

variable "subnet_ids" {
  description = "The IDs of the existing subnets"
  type        = list(string)
}

variable "iam_node_group_role" {
  description = "The name of the existing IAM node group role"
  type        = string
}

variable "iam_cluster_role" {
  description = "The name of the existing IAM cluster role"
  type        = string
}

variable "iam_cluster_autoscaler_role" {
  description = "The name of the existing IAM cluster autoscaler role"
  type        = string
}

variable "aws_region" {
  description = "The AWS region"
  type        = string
  default = "ap-south-1"
}

# configure the AWS provider
provider "aws" {
  region = var.aws_region
}

# data resources to reference existing VPC and subnets
data "aws_vpc" "prod_vpc" {
  id = var.vpc_id
}

data "aws_subnet" "prod_vpc_subnets" {
  count = length(var.subnet_ids)
  id    = element(var.subnet_ids, count.index)
}


# data resources to reference existing iam roles
data "aws_iam_role" "eks_node_role" {
  name = var.iam_node_group_role
} # we might need to add eks:UpdateNodegroupConfig

data "aws_iam_role" "eks_cluster_role" {
  name = var.iam_cluster_role
}

data "aws_iam_role" "eks_cluster_autoscaler_role" {
  name = var.iam_cluster_autoscaler_role
}

# create eks cluster and kubernetes provider
resource "aws_eks_cluster" "prod_eks_cluster" {
  name     = "dalgo-prod-cluster"
  role_arn = data.aws_iam_role.eks_cluster_role.arn
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = data.aws_subnet.prod_vpc_subnets[*].id
  }

  enabled_cluster_log_types = ["audit", "api", "authenticator", "scheduler", "controllerManager"]
}

resource "aws_security_group" "eks_cluster" {
  name        = "eks-prod-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = data.aws_vpc.prod_vpc.id

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
    Name = "eks-prod-cluster-sg"
  }
}

resource "aws_security_group" "eks_nodes" {
  name        = "eks-prod-nodes-sg"
  description = "Security group for worker nodes"
  vpc_id      = data.aws_vpc.prod_vpc.id

  tags = {
    Name                                          = "eks-prod-nodes-sg"
    "kubernetes.io/cluster/dalgo-prod-cluster"    = "owned"
  }
}

# Allow inbound traffic from the cluster security group
resource "aws_security_group_rule" "nodes_inbound_cluster" {
  description              = "Allow worker nodes to receive communication from the cluster control plane"
  from_port                = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
  to_port                  = 65535
  type                     = "ingress"
}

# Allow all outbound traffic
resource "aws_security_group_rule" "nodes_outbound" {
  description       = "Allow all outbound traffic"
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  security_group_id = aws_security_group.eks_nodes.id
  cidr_blocks       = ["0.0.0.0/0"]
}

# Allow nodes to communicate with each other
resource "aws_security_group_rule" "nodes_internal" {
  description              = "Allow nodes to communicate with each other"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_nodes.id
}

# Allow worker nodes to access the cluster API Server
resource "aws_security_group_rule" "cluster_inbound" {
  description              = "Allow worker nodes to communicate with the cluster API Server"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_cluster.id
}

# Common ports needed for worker nodes
resource "aws_security_group_rule" "nodes_kubelet" {
  description       = "Allow kubelet API"
  type              = "ingress"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes.id
  cidr_blocks       = [aws_vpc.prod_vpc.cidr_block]
}

resource "aws_security_group_rule" "nodes_kubeproxy" {
  description       = "Allow kube-proxy"
  type              = "ingress"
  from_port         = 10256
  to_port           = 10256
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes.id
  cidr_blocks       = [aws_vpc.prod_vpc.cidr_block]
}

resource "aws_security_group_rule" "nodes_nodeports" {
  description       = "Allow NodePort Services"
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes.id
  cidr_blocks       = ["0.0.0.0/0"]
}

provider "kubernetes" {
  host                   = aws_eks_cluster.prod_eks_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.prod_eks_cluster.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.prod_eks_cluster.name, "--region", var.aws_region]
    command     = "aws"
  }
}

# create node group and its instances
resource "aws_eks_node_group" "prod_eks_node_group" {
  cluster_name    = aws_eks_cluster.prod_eks_cluster.name
  node_group_name = "prod-node-group"
  node_role_arn   = data.aws_iam_role.eks_node_role.arn
  subnet_ids      = var.subnet_ids
  instance_types  = ["t4g.large"]

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 10
  }

  # This AMI type matches current AMI deployed on production. Might be useful to compare other 
  # performant instance type
  ami_type = "AL2023_ARM_64_STANDARD"


  # Add the security group to the node group
  remote_access {
    ec2_ssh_key = "dalgo-eks-ec2-key-pair" # Optional: Replace with your SSH key pair name if needed
  }

  tags = {
    Environment = "production"
    
  }

}

# cluster autoscaler
resource "kubernetes_service_account" "kube_service_acc_user" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = data.aws_iam_role.eks_cluster_autoscaler_role.arn
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
            "--nodes=1:5:dalgo-prod-cluster",
            "--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/dalgo-prod-cluster"
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