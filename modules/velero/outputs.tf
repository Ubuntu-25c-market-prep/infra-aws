output "role_arn" {
  description = "IRSA role ARN for the Velero server. Consumed by the velero-irsa ConfigMap in flux-system, since the ARN carries the account id and gitops-flux is public."
  value       = aws_iam_role.velero.arn
}

output "bucket_name" {
  description = "S3 bucket name for Velero backups. Consumed by the gitops-flux HelmRelease's BackupStorageLocation config."
  value       = aws_s3_bucket.velero.id
}

output "bucket_arn" {
  description = "S3 bucket ARN, for reference by anything auditing what the Velero role can reach."
  value       = aws_s3_bucket.velero.arn
}
