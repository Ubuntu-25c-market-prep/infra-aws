# Surfaces the module's result so `terraform output` can show it after apply.
# This feeds the out-of-band ConfigMap that the gitops-flux HelmRelease reads.

output "controller_role_arn" {
  description = "IRSA role ARN for the external-dns controller. Consumed by the external-dns-irsa ConfigMap in flux-system, since the ARN carries the account id and gitops-flux is public."
  value       = module.external_dns.controller_role_arn
}
