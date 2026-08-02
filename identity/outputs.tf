output "identity_store_id" {
  description = "Directory holding the users and groups."
  value       = local.identity_store_id
}

output "access_portal_url" {
  description = <<-EOT
    The one link everybody signs in at. The subdomain is set in the console, is
    irreversible, and is recorded here via access_portal_subdomain so this output
    matches what people are actually told to open.
  EOT
  value = format(
    "https://%s.awsapps.com/start",
    var.access_portal_subdomain != "" ? var.access_portal_subdomain : local.identity_store_id,
  )
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
