###############################################################################
# The EKS cluster itself, plus the OIDC provider it needs for IRSA later.
#
# IPv4 (no kubernetes_network_config - the default ip_family is ipv4). Runs in
# the VPC's public subnets, which is all our topology has (ADR 0005).
###############################################################################

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.control_plane.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.control_plane.id]
    endpoint_private_access = true # nodes inside the VPC reach the API server
    endpoint_public_access  = true # you can run kubectl from your laptop
    # Note: public access defaults to 0.0.0.0/0. ADR 0005 wants this restricted
    # to known CIDRs - a later hardening step, not done here.
  }

  # Modern access management: entries are AWS resources, not the aws-auth
  # ConfigMap. The principal that runs this apply becomes cluster admin, and a
  # managed node group registers its node role automatically.
  access_config {
    authentication_mode = var.authentication_mode
  }

  # The control-plane role's policy must be attached before the cluster is
  # created; Terraform cannot infer this ordering on its own.
  depends_on = [aws_iam_role_policy_attachment.control_plane]

  tags = {
    Name = var.cluster_name
  }
}

###############################################################################
# OIDC provider - lets Kubernetes service accounts assume IAM roles (IRSA).
# Needed later for add-ons like the EBS CSI driver; harmless to create now.
###############################################################################

# Fetches the OIDC issuer's TLS certificate so the provider below can trust it.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}
