output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint. Used to build a kubeconfig."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA certificate for the API server. Used to build a kubeconfig."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group attached to the worker nodes."
  value       = aws_security_group.node.id
}

output "node_role_arn" {
  description = "IAM role the worker nodes run as."
  value       = aws_iam_role.node.arn
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN. Used by IRSA roles for add-ons."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL (without https://). Used in IRSA trust policies."
  value       = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

output "ebs_csi_irsa_role_arn" {
  description = "ARN of the IRSA role the EBS CSI controller service account assumes. Consumed by the Flux HelmRelease as the eks.amazonaws.com/role-arn annotation on kube-system/ebs-csi-controller-sa. null when create_ebs_csi_irsa is false."
  value       = one(aws_iam_role.ebs_csi[*].arn)
}
