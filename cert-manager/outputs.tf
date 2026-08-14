# Surfaces the module's result so `terraform output` can show it after apply.
# This feeds the out-of-band ConfigMap that the gitops-flux HelmRelease reads.

output "controller_role_arn" {
  description = "IRSA role ARN for the cert-manager controller. Consumed by the cert-manager-irsa ConfigMap in flux-system, since the ARN carries the account id and gitops-flux is public."
  value       = module.cert_manager.controller_role_arn
}