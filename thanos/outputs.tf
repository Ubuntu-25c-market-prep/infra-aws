output "thanos_role_arn" {
  description = "IRSA role ARN for the Thanos sidecar. Used in the gitops-flux HelmRelease to annotate the Prometheus service account."
  value       = aws_iam_role.thanos.arn
}

output "thanos_bucket_name" {
  description = "S3 bucket name for Thanos metric blocks."
  value       = aws_s3_bucket.thanos.id
}
