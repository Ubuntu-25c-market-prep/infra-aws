output "identity_store_id" {
  description = "Directory holding the users and groups."
  value       = local.identity_store_id
}

output "access_portal_url" {
  description = <<-EOT
    The one link everybody signs in at. Customising the subdomain is a console
    action and is IRREVERSIBLE - see ops-program/runbooks/onboard-to-aws.md.
  EOT
  value       = "https://${local.identity_store_id}.awsapps.com/start"
}

output "permission_set_arns" {
  description = "Permission sets by short name, for verifying assignments."
  value       = local.permission_set_arns
}

output "group_ids" {
  description = "Access group ids. Workstream groups are intentionally excluded - they grant nothing."
  value       = { for k, g in aws_identitystore_group.access : k => g.group_id }
}

output "sign_in_names" {
  description = "GitHub handle -> Identity Center sign-in name. They are the same by design."
  value       = { for h, u in aws_identitystore_user.this : h => u.user_name }
}
