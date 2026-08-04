###############################################################################
# Launch template for the worker nodes.
#
# A bare managed node group cannot do either of these, which is why we add one:
#   1. Attach our own node security group (security_groups.tf).
#   2. Enforce IMDSv2 with hop limit 1 (ADR 0005). This is what stops a pod from
#      reaching the instance metadata service and stealing the node's IAM role
#      credentials. Non-negotiable.
#
# We deliberately set no image_id and no user_data: EKS still manages the
# optimized AMI and node bootstrap for a managed node group. We only override
# the security groups and metadata options.
###############################################################################

resource "aws_launch_template" "node" {
  name_prefix = "${var.cluster_name}-node-"

  vpc_security_group_ids = [
    # Our rules (node-to-node, control-plane-to-kubelet, egress).
    aws_security_group.node.id,
    # The EKS-managed cluster security group, so control-plane <-> node traffic
    # keeps working the way EKS expects.
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
  ]

  # IMDSv2 required, hop limit 1 (ADR 0005).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only - reject plain IMDSv1
    http_put_response_hop_limit = 1          # a pod is one hop away, so it cannot reach IMDS
  }

  # Name the EC2 instances the node group launches from this template.
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-node"
    }
  }
}
