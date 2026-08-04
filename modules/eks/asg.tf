###############################################################################
# Worker nodes - a managed node group. EKS creates and runs the underlying Auto
# Scaling Group; we just declare the size and instance type.
#
# Placed in the VPC's public subnets (all our topology has, ADR 0005). Because
# the subnets set map_public_ip_on_launch, the nodes get public IPs and reach
# the internet directly - no NAT.
###############################################################################

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.instance_types

  # Use our launch template - this is what applies the node SG and IMDSv2
  # hop-limit-1. latest_version keeps the node group on the newest template.
  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  # The node role's policies must be attached before nodes try to join, or they
  # register without permission to pull images or set up pod networking.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  tags = {
    Name = "${var.cluster_name}-ng"
  }
}
