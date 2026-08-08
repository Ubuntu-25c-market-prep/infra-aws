# Surfaces the module's results so `terraform output` can show them after apply.

output "repository_urls" {
  description = "Push/pull URL of each repository, keyed by short image name."
  value       = module.ecr.repository_urls
}

output "repository_arns" {
  description = "ARN of each repository, keyed by short image name."
  value       = module.ecr.repository_arns
}

output "registry_url" {
  description = "Registry host to docker login against."
  value       = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}
