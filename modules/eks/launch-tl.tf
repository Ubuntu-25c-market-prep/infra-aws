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

  # Raise the kubelet's pod ceiling.
  #
  # A node's --max-pods is fixed at boot. EKS's AL2023 bootstrap derives it from
  # the instance type's ENI limits - ENIs x (IPs_per_ENI - 1) + 2, which is 17 on
  # a t3.medium - and it does NOT notice that the VPC CNI has prefix delegation
  # enabled. So enabling prefix delegation alone changes nothing here; the value
  # has to be stated, and the nodes have to be replaced to pick it up.
  #
  # PREREQUISITE: ENABLE_PREFIX_DELEGATION must already be true on every aws-node
  # pod (gitops-flux infrastructures/base/aws-vpc-cni). A node that advertises
  # this many slots while the CNI can only hand out 17 IPs schedules pods it
  # cannot give addresses to, and they hang in ContainerCreating.
  #
  # AL2023 takes bootstrap settings as a NodeConfig document in MIME multipart
  # user data; EKS appends its own part to what we set here and merges them.
  user_data = var.max_pods == null ? null : base64encode(<<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="//"

    --//
    Content-Type: application/node.eks.aws

    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      kubelet:
        config:
          maxPods: ${var.max_pods}
    --//--
  EOT
  )
}
