# Surfaces the module's results so `terraform output` can show them after apply.

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN, for IRSA roles."
  value       = module.eks.oidc_provider_arn
}
