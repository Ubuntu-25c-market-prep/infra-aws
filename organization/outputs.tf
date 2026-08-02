output "organization_id" {
  description = "Organisation id, needed by the organisation CloudTrail bucket policy."
  value       = aws_organizations_organization.this.id
}

output "root_id" {
  description = "Organisation root. Nothing should be attached here except by hand."
  value       = aws_organizations_organization.this.roots[0].id
}

output "workloads_ou_id" {
  description = "OU holding the single workload account."
  value       = aws_organizations_organizational_unit.workloads.id
}

output "dormant_ou_id" {
  description = "OU holding Staging and Prod."
  value       = aws_organizations_organizational_unit.dormant.id
}

output "guardrail_policy_id" {
  description = "SCP applied to the workloads OU."
  value       = aws_organizations_policy.guardrails.id
}

output "detach_guardrails_command" {
  description = "Break-glass. Run from the management account; SCPs cannot block it there."
  value       = <<-EOT
    aws organizations detach-policy \
      --policy-id ${aws_organizations_policy.guardrails.id} \
      --target-id ${aws_organizations_organizational_unit.workloads.id}
  EOT
}
