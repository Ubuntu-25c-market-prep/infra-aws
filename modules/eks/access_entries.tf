###############################################################################
# Cluster access - who may administer the cluster.
#
# authentication_mode = "API" means access comes ONLY from access entries (no
# aws-auth ConfigMap). We deliberately did NOT set
# bootstrap_cluster_creator_admin_permissions, so admins are listed explicitly
# here - reproducible, unlike a manual `aws eks create-access-entry`.
#
# Do NOT add the node role here: the managed node group creates its own access
# entry automatically, and a second one would conflict.
###############################################################################

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  # The entry must exist before a policy can be associated with it.
  depends_on = [aws_eks_access_entry.admin]
}
