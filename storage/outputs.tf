output "app_data_bucket" {
  description = "Application data bucket name."
  value       = module.app_data.id
}

output "app_data_bucket_arn" {
  description = "Application data bucket ARN, for IAM policy resource blocks."
  value       = module.app_data.arn
}
