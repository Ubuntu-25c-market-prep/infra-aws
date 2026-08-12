###############################################################################
# Node role - assumed by the EC2 instances Karpenter launches.
#
# Dedicated role (not the managed node group's u25c-shared-node) so Karpenter's
# node identity is separate from the bootstrap node group. It carries the same
# managed policies the upstream Karpenter template uses. Karpenter itself
# creates and manages the *instance profile* for this role at runtime (the
# controller policy grants the scoped iam:*InstanceProfile actions), so we do
# not create an aws_iam_instance_profile here.
###############################################################################

data "aws_partition" "current" {}

resource "aws_iam_role" "node" {
  name                 = "${var.cluster_name}-karpenter-node"
  permissions_boundary = var.permissions_boundary

  # Only EC2 instances may assume this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.cluster_name}-karpenter-node"
  }
}

# The four managed policies from the upstream Karpenter node role: register with
# the cluster, pod networking (VPC CNI), pull images from ECR, and SSM (for
# node debugging / SSM-based AMI resolution).
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

###############################################################################
# Cluster access entry for the node role.
#
# authentication_mode is API, so a node's IAM role only joins the cluster if it
# has an access entry. The managed node group creates its own automatically;
# this dedicated Karpenter node role does NOT, so without this entry Karpenter
# nodes launch and then silently fail to register. Type EC2_LINUX grants the
# standard node permissions - no access policy association is needed.
###############################################################################

resource "aws_eks_access_entry" "node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
}
