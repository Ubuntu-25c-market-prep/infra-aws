###############################################################################
# Discovery tags.
#
# The EC2NodeClass (in gitops-flux) selects subnets and security groups by the
# tag karpenter.sh/discovery=<cluster_name>. We tag the two public subnets and
# BOTH the node SG and the EKS-managed cluster SG, so Karpenter-launched nodes
# get the same security-group set the managed node group's launch template
# attaches - node-to-node plus control-plane connectivity.
#
# aws_ec2_tag manages a single tag on a resource owned elsewhere (subnets in the
# network layer, the cluster SG by EKS) without taking over the whole resource.
###############################################################################

resource "aws_ec2_tag" "subnet_discovery" {
  for_each = toset(var.subnet_ids)

  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

resource "aws_ec2_tag" "node_sg_discovery" {
  resource_id = var.node_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

resource "aws_ec2_tag" "cluster_sg_discovery" {
  resource_id = var.cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}
