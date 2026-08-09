###############################################################################
# EKS managed add-ons.
#
# These are AWS API objects, not Helm charts: the control plane installs them
# and keeps them version-matched to the cluster. They are deliberately NOT
# delivered by Flux - without vpc-cni pods get no IP addresses, including
# Flux's own, so anything the cluster needs in order to run Flux cannot come
# from Flux.
#
# vpc-cni, coredns and kube-proxy already exist as self-managed defaults from
# cluster creation, which is why resolve_conflicts_on_create is OVERWRITE -
# without it, adopting them fails with "already exists".
#
# On update the choice flips to PRESERVE: an add-on's config may legitimately
# have been changed in-cluster, and an upgrade should not silently discard it.
###############################################################################

resource "aws_eks_addon" "this" {
  for_each = var.cluster_addons

  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.key

  # Empty string means "whatever EKS ships as default for this Kubernetes
  # version" - the usual case. Pin only when a specific build is required.
  addon_version = each.value != "" ? each.value : null

  # Settings we declare, as JSON. Empty object when this add-on has no entry in
  # cluster_addon_config, which leaves it entirely on add-on defaults.
  configuration_values = jsonencode(lookup(var.cluster_addon_config, each.key, {}))

  resolve_conflicts_on_create = "OVERWRITE"

  # OVERWRITE only where we actually declare configuration - there Terraform is
  # the source of truth and anything changed in-cluster should lose. For an
  # add-on we do not configure, PRESERVE: taking OVERWRITE on all of them would
  # mean an unrelated change could reset config we never described.
  resolve_conflicts_on_update = lookup(var.cluster_addon_config, each.key, null) != null ? "OVERWRITE" : "PRESERVE"

  # Only the EBS CSI driver needs its own identity; the rest are covered by the
  # node role's policies.
  service_account_role_arn = each.key == "aws-ebs-csi-driver" ? one(aws_iam_role.ebs_csi[*].arn) : null

  # coredns and the CSI controller are Deployments - they need somewhere to be
  # scheduled, or the add-on reports Degraded until nodes appear.
  depends_on = [aws_eks_node_group.this]

  # Org, Env, Workstream, ManagedBy and Repo come from the provider's
  # default_tags and satisfy the org tag policy (organization/policies.tf).
  # Component groups the four add-ons for inventory and Resource Groups - not
  # for cost, since add-ons are pods on the nodes and are not billed as
  # resources. PascalCase to match the governed tag keys.
  tags = {
    Name      = "${var.cluster_name}-${each.key}"
    Component = "platform-tools"
  }
}

###############################################################################
# IRSA role for the EBS CSI driver.
#
# Unlike the other three, this one is not installed by default and has no
# policy on the node role. It needs to create and attach EBS volumes, which is
# an AWS permission, so it gets its own role assumed through the cluster's OIDC
# provider.
###############################################################################

locals {
  ebs_csi_enabled = contains(keys(var.cluster_addons), "aws-ebs-csi-driver")

  # The provider URL without the scheme - IAM condition keys are written
  # against the bare host and path.
  oidc_host = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

resource "aws_iam_role" "ebs_csi" {
  count = local.ebs_csi_enabled ? 1 : 0

  name                 = "${var.cluster_name}-ebs-csi"
  permissions_boundary = var.permissions_boundary

  # The `sub` condition is what scopes this role to ONE service account in ONE
  # namespace. Without it the role is assumable by any pod in any namespace of
  # this cluster - including a developer namespace - which in a single-cluster,
  # namespace-per-environment platform is a privilege escalation path.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.cluster_name}-ebs-csi"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = local.ebs_csi_enabled ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
