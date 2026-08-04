output "repository_urls" {
  description = "Push/pull URL of each repository, keyed by short image name. This is what a docker push targets and what a Kubernetes image reference uses."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "ARN of each repository, keyed by short image name. Use these to scope an IAM policy to specific repositories rather than to *."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

output "repository_names" {
  description = "Full name of each repository, keyed by short image name (e.g. api -> u25c/api)."
  value       = { for k, r in aws_ecr_repository.this : k => r.name }
}

output "registry_id" {
  description = "Account id that owns the registry."
  value       = one(values(aws_ecr_repository.this)[*].registry_id)
}
