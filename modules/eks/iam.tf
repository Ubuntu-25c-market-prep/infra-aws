###############################################################################
# IAM roles for EKS: one for the control plane, one for the worker nodes.
# The difference between them is WHO may assume each (the trust policy).
###############################################################################

###############################################################################
# Cluster (control-plane) role - assumed by the EKS service itself.
###############################################################################

resource "aws_iam_role" "control_plane" {
  name                 = "${var.cluster_name}-control-plane"
  permissions_boundary = var.permissions_boundary

  # Trust policy: only the EKS service may assume this role - not you, not nodes.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.cluster_name}-control-plane"
  }
}

# Lets the control plane manage cluster-related AWS resources on your behalf.
resource "aws_iam_role_policy_attachment" "control_plane" {
  role       = aws_iam_role.control_plane.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

###############################################################################
# Node role - assumed by the EC2 worker nodes.
###############################################################################

resource "aws_iam_role" "node" {
  name                 = "${var.cluster_name}-node"
  permissions_boundary = var.permissions_boundary

  # Trust policy: EC2 instances (the worker nodes) may assume this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.cluster_name}-node"
  }
}

# Register with the cluster.
resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Pod networking: create ENIs, assign pod IPs (the VPC CNI).
resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Pull container images from ECR (read-only).
resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
