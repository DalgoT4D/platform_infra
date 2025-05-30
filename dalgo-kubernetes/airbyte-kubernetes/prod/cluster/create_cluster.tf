provider "aws" {
  region = "ap-south-1" 
}

# ================== terraform state management =====================
# S3 Bucket for State
resource "aws_s3_bucket" "terraform_state" {
  bucket = "production-eks-terraform-state"
}

# Enable versioning
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "production-terraform-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# Terraform Backend Configuration
terraform {
  backend "s3" {
    bucket         = "production-eks-terraform-state"
    key            = "global/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "production-terraform-state-locks"
    encrypt        = true
  }
}

# ================== eks cluster creation =====================
# IAM Roles and Policies for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks_cluster_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# VPC and Networking Configuration
# Reference default VPC
data "aws_vpc" "default" {
  id = "vpc-060665f96234a5997"
}

# Variables for subnet IDs
variable "subnet_ids" {
  type    = list(string)
  default = [
    "subnet-037b037950ab1312e",  # eks-prod-private
    "subnet-06f6ab26aabc1dd07"   # eks-prod-public
  ]
}

# fetch existing subnets
data "aws_subnet" "existing" {
  count = 2
  id    = var.subnet_ids[count.index]
}


# EKS Cluster Configuration
resource "aws_eks_cluster" "production_cluster" {
  name     = "dalgo-production-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  depends_on                = [aws_iam_role_policy_attachment.eks_cluster_policy]
  enabled_cluster_log_types = ["audit", "api", "authenticator", "scheduler", "controllerManager"]
}

# Kubeconfig Update; didn't work well so consider removing it if not useful
resource "null_resource" "update_kubeconfig" {
  triggers = {
    always_run = "${timestamp()}" # This ensures it runs every time
  }

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${aws_eks_cluster.production_cluster.name} --region ap-south-1 --role arn:aws:iam::024209611402:role/AWSReservedSSO_EKSClusterManagement_4e8ae473c740206e"
  }
}

provider "kubernetes" {
  host                   = aws_eks_cluster.production_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.production_cluster.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.production_cluster.name, "--region", "ap-south-1"]
    command     = "aws"
  }

}

data "aws_nat_gateway" "nat_gateway" {
  id = "nat-017eeba08b22d5975"
}

resource "aws_route_table" "public_route_table" {
  vpc_id = data.aws_vpc.default.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = data.aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = 1
  subnet_id      = "subnet-06f6ab26aabc1dd07" # eks-prod-public
  route_table_id = aws_route_table.public_route_table.id
}

# ================ policies for the node group ================
resource "aws_iam_role" "eks_node_group_role" {
  name = "eks_node_group_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "eks.amazonaws.com" # Allows EKS to assume this role
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_group_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group_role.name
}


resource "aws_security_group" "eks_cluster" {
  name        = "eks-production-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = data.aws_vpc.default.id

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
    Name = "eks-production-cluster-sg"
  }
}

resource "aws_security_group" "eks_nodes" {
  name        = "eks-production-nodes-sg"
  description = "Security group for worker nodes"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name                                          = "eks-production-nodes-sg"
    "kubernetes.io/cluster/dalgo-production-cluster" = "owned"
  }
}

# Allow inbound traffic from the cluster security group
resource "aws_security_group_rule" "nodes_inbound_cluster" {
  description              = "Allow worker nodes to receive communication from the cluster control plane"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
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

resource "aws_security_group_rule" "nodes_kubelet" {
  description       = "Allow kubelet API"
  type              = "ingress"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes.id
  cidr_blocks       = [data.aws_vpc.default.cidr_block]
}

resource "aws_security_group_rule" "nodes_kubeproxy" {
  description       = "Allow kube-proxy"
  type              = "ingress"
  from_port         = 10256
  to_port           = 10256
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes.id
  cidr_blocks       = [data.aws_vpc.default.cidr_block]
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

# ==================== the node group ===============
resource "aws_eks_node_group" "my_node_group" {
  node_group_name = "production-node-group"
  cluster_name    = aws_eks_cluster.production_cluster.name
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = var.subnet_ids
  instance_types  = ["t4g.large"]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  # This AMI type matches current AMI deployed on production. Might be useful to compare other 
  # performant instance type
  ami_type = "AL2023_ARM_64_STANDARD"


  # Add the security group to the node group
  remote_access {
    ec2_ssh_key               = "dalgo-eks-ec2-key-pair" # Optional: Replace with your SSH key pair name if needed
    source_security_group_ids = [aws_security_group.eks_nodes.id]
  }

  tags = {
    Environment = "production"
    "k8s.io/cluster-autoscaler/enabled" = "true"
    "k8s.io/cluster-autoscaler/dalgo-production-cluster" = "owned"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_policy
  ]
}

# openid connect provider (why do we need this)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.production_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.production_cluster.identity[0].oidc[0].issuer
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
  name               = "eks-cluster-autoscaler"
}

resource "aws_iam_policy" "eks_cluster_autoscaler_iam_policy" {
  name = "eks-cluster-autoscaler"

  policy = jsonencode({
    Statement = [{
      Action = [
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
        "eks:DescribeNodegroup"
      ]
      Effect   = "Allow"
      Resource = "*",
      # Condition = {
      #   StringEquals = {
      #     "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled" = "true",
      #     "aws:ResourceTag/k8s.io/cluster-autoscaler/dalgo-production-cluster" = "owned"
      #   }
      # }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_autoscaler_attach" {
  role       = aws_iam_role.eks_cluster_autoscaler_role.name
  policy_arn = aws_iam_policy.eks_cluster_autoscaler_iam_policy.arn
}

resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.eks_cluster_autoscaler_role.arn
    }
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
        service_account_name = kubernetes_service_account.cluster_autoscaler.metadata[0].name

        container {
          name  = "cluster-autoscaler"
          image = "k8s.gcr.io/autoscaling/cluster-autoscaler:v1.32.0"

          command = [
            "./cluster-autoscaler",
            "--v=4",
            "--stderrthreshold=info",
            "--cloud-provider=aws",
            "--skip-nodes-with-local-storage=false",
            "--expander=least-waste",
            "--nodes=1:5:dalgo-production-cluster",
            "--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/dalgo-production-cluster"
          ]

          env {
            name  = "AWS_REGION"
            value = "ap-south-1"
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

resource "kubernetes_cluster_role" "cluster_autoscaler_kube_cluster_role" {
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

resource "kubernetes_cluster_role_binding" "cluster_autoscaler_kube_cluster_role_binding" {
  metadata {
    name = "cluster-autoscaler"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.cluster_autoscaler_kube_cluster_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.cluster_autoscaler.metadata[0].name
    namespace = kubernetes_service_account.cluster_autoscaler.metadata[0].namespace
  }
}

resource "kubernetes_role" "cluster_autoscaler" {
  metadata {
    name = "cluster-autoscaler"
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["create", "list", "watch"]
  }

  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = ["cluster-autoscaler-status", "cluster-autoscaler-priority-expander"]
    verbs          = ["delete", "get", "update", "watch"]
  }
}

resource "kubernetes_role_binding" "cluster_autoscaler" {
  metadata {
    name = "cluster-autoscaler"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.cluster_autoscaler.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.cluster_autoscaler.metadata[0].name
    namespace = kubernetes_service_account.cluster_autoscaler.metadata[0].namespace
  }
}
