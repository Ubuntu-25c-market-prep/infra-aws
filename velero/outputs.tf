output "velero_role_arn" {
  description = "IRSA role ARN for the Velero server. Used in the gitops-flux HelmRelease to annotate the Velero service account."
  value       = module.velero.role_arn
}

output "velero_bucket_name" {
  description = "S3 bucket name for Velero backups. Used in the gitops-flux HelmRelease's BackupStorageLocation config."
  value       = module.velero.bucket_name
}
