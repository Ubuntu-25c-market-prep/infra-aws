# Surfaces the module's results so `terraform output` can show them after apply.
# These feed the gitops-flux HelmRelease values and the EC2NodeClass.

output "controller_role_arn" {
  description = "IRSA role ARN for the Karpenter controller. Annotate the Helm serviceAccount with eks.amazonaws.com/role-arn = this."
  value       = module.karpenter.controller_role_arn
}

output "node_role_name" {
  description = "Node role name for the Karpenter EC2NodeClass spec.role (bare name, not ARN)."
  value       = module.karpenter.node_role_name
}

output "interruption_queue_name" {
  description = "Interruption SQS queue name for the Helm values settings.interruptionQueue."
  value       = module.karpenter.interruption_queue_name
}

output "discovery_tag_value" {
  description = "Value of karpenter.sh/discovery on the subnets and security groups; the EC2NodeClass selector matches this."
  value       = module.karpenter.discovery_tag_value
}
