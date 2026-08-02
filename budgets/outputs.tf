output "freeze_policy_id" {
  description = "SCP attached to workload accounts when the ceiling trips."
  value       = aws_organizations_policy.cost_freeze.id
}

output "budget_name" {
  value = aws_budgets_budget.org_monthly.name
}

output "detach_freeze_command" {
  description = "Run this to lift the freeze after remediating."
  value = join(" ", [
    "aws organizations detach-policy --policy-id",
    aws_organizations_policy.cost_freeze.id,
    "--target-id <account-id>",
  ])
}
