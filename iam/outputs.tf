output "plan_role_arn" {
  description = "Set as AWS_PLAN_ROLE_ARN in GitHub Actions variables."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Set as AWS_APPLY_ROLE_ARN in GitHub Actions variables."
  value       = aws_iam_role.apply.arn
}

output "infra_v2_apply_role_arn" {
  description = "Set as AWS_ROLE_ARN_APPLY in terraform-infra-v2's GitHub environments."
  value       = aws_iam_role.infra_v2_apply.arn
}

output "engineer_boundary_policy_name" {
  description = "Pass to ../identity as engineer_boundary_policy_name."
  value       = aws_iam_policy.engineer_boundary.name
}

output "engineer_boundary_policy_arn" {
  description = "Permissions boundary for Identity Center engineers."
  value       = aws_iam_policy.engineer_boundary.arn
}
