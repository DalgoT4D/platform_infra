provider "aws" {
  region = "ap-south-1"  # Change to your desired region
}

resource "aws_eks_cluster" "my_cluster" {
  name     = "my-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = aws_subnet.my_subnet[*].id
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
  enabled_cluster_log_types = ["audit", "api", "authenticator","scheduler", "controllerManager"]
}

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

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "my_subnet" {
  count             = 2
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
}

data "aws_availability_zones" "available" {}

# Create the NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  subnet_id    = aws_subnet.my_subnet[0].id  # Use a public subnet for the NAT Gateway

  tags = {
    Name = "nat-gateway"
  }
}

# Create a route table for the private subnet
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "private-route-table"
  }
}

# Associate the private subnet with the route table
resource "aws_route_table_association" "private_subnet_association" {
  count          = 1  
  subnet_id      = aws_subnet.my_subnet[0].id
  route_table_id = aws_route_table.private_route_table.id
}


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


# EKS Cluster Security Group
resource "aws_security_group" "eks_cluster" {
  name        = "eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.my_vpc.id

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
    Name = "eks-cluster-sg"
  }
}

# Worker Nodes Security Group
resource "aws_security_group" "eks_nodes" {
  name        = "eks-nodes-sg"
  description = "Security group for worker nodes"
  vpc_id      = aws_vpc.my_vpc.id

  tags = {
    Name = "eks-nodes-sg"
    "kubernetes.io/cluster/my-eks-cluster" = "owned"
  }
}

# Worker Node Security Group Rules

# Allow inbound traffic from the cluster security group
resource "aws_security_group_rule" "nodes_inbound_cluster" {
  description              = "Allow worker nodes to receive communication from the cluster control plane"
  from_port               = 0
  protocol                = "-1"
  security_group_id       = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.eks_cluster.id
  to_port                 = 65535
  type                    = "ingress"
}

# Allow all outbound traffic
resource "aws_security_group_rule" "nodes_outbound" {
  description       = "Allow all outbound traffic"
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.eks_nodes.id
  cidr_blocks       = ["0.0.0.0/0"]
  to_port           = 65535
  type              = "egress"
}

# Allow nodes to communicate with each other
resource "aws_security_group_rule" "nodes_internal" {
  description              = "Allow nodes to communicate with each other"
  from_port               = 0
  protocol                = "-1"
  security_group_id       = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.eks_nodes.id
  to_port                 = 65535
  type                    = "ingress"
}

# Allow worker nodes to access the cluster API Server
resource "aws_security_group_rule" "cluster_inbound" {
  description              = "Allow worker nodes to communicate with the cluster API Server"
  from_port               = 443
  protocol                = "tcp"
  security_group_id       = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_nodes.id
  to_port                 = 443
  type                    = "ingress"
}

# Common ports needed for worker nodes
resource "aws_security_group_rule" "nodes_kubelet" {
  description       = "Allow kubelet API"
  from_port         = 10250
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes.id
  cidr_blocks       = [aws_vpc.my_vpc.cidr_block]
  to_port           = 10250
  type              = "ingress"
}

resource "aws_security_group_rule" "nodes_kubeproxy" {
  description       = "Allow kube-proxy"
  from_port         = 10256
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes.id
  cidr_blocks       = [aws_vpc.my_vpc.cidr_block]
  to_port           = 10256
  type              = "ingress"
}

resource "aws_security_group_rule" "nodes_nodeports" {
  description       = "Allow NodePort Services"
  from_port         = 30000
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes.id
  cidr_blocks       = ["0.0.0.0/0"]
  to_port           = 32767
  type              = "ingress"
}

# Update EKS Node Group to use the security group
resource "aws_eks_node_group" "my_node_group" {
  cluster_name    = aws_eks_cluster.my_cluster.name
  node_group_name = "my-node-group"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = aws_subnet.my_subnet[*].id
  instance_types  = ["t4g.large"]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  ami_type = "AL2023_ARM_64_STANDARD" 


  # Add the security group to the node group
  remote_access {
    ec2_ssh_key = "your-key-pair-name"  # Optional: Replace with your SSH key pair name if needed
    source_security_group_ids = [aws_security_group.eks_nodes.id]
  }

  tags = {
    Environment = "production"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_policy
  ]
}

# Create an Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my-internet-gateway"
  }
}

# Create a route table for the public subnet
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}


# Associate the public subnet with the route table
resource "aws_route_table_association" "public_subnet_association" {
  count          = 1  
  subnet_id      = aws_subnet.my_subnet[0].id 
  route_table_id = aws_route_table.public_route_table.id
}