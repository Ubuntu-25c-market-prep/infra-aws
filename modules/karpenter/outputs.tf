# Consumed by the eks layer's outputs, then wired into the gitops-flux
# HelmRelease values and the EC2NodeClass.

output "controller_role_arn" {
  description = "IRSA role ARN for the Karpenter controller. Goes on the Helm serviceAccount annotation eks.amazonaws.com/role-arn."
  value       = aws_iam_role.controller.arn
}

output "node_role_name" {
  description = "Name of the node role Karpenter's EC2NodeClass references (spec.role). Not the ARN - the EC2NodeClass wants the bare name."
  value       = aws_iam_role.node.name
}

output "node_role_arn" {
  description = "ARN of the Karpenter node role."
  value       = aws_iam_role.node.arn
}

output "interruption_queue_name" {
  description = "Name of the interruption SQS queue. Goes into the Helm values settings.interruptionQueue."
  value       = aws_sqs_queue.interruption.name
}

output "discovery_tag_value" {
  description = "Value of the karpenter.sh/discovery tag on subnets and security groups. The EC2NodeClass selector matches this."
  value       = var.cluster_name
}
