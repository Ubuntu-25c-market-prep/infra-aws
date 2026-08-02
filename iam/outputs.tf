output "plan_role_arn" {
  description = "Set as AWS_PLAN_ROLE_ARN in GitHub Actions variables."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Set as AWS_APPLY_ROLE_ARN in GitHub Actions variables."
  value       = aws_iam_role.apply.arn
}
