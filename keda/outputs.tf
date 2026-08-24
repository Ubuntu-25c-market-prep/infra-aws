# Surfaces the module's result so `terraform output` can show it after apply.
# This feeds the out-of-band ConfigMap that the gitops-flux HelmRelease reads.

output "operator_role_arn" {
  description = "IRSA role ARN for the KEDA operator. Consumed by the keda-irsa ConfigMap in flux-system, since the ARN carries the account id and gitops-flux is public."
  value       = module.keda.operator_role_arn
}
