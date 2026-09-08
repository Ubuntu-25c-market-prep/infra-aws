###############################################################################
# Inputs for the Velero AWS-side prerequisites. The in-cluster install
# (HelmRelease, Schedules, BackupStorageLocation, VolumeSnapshotLocation) lives
# in gitops-flux; this module only creates what has to exist in AWS: the backup
# bucket and the IRSA role Velero authenticates as when it talks to S3 and EC2.
###############################################################################

variable "cluster_name" {
  description = "EKS cluster name. Used in the IAM role name so roles stay identifiable per cluster."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider. The federated principal in the Velero role's trust policy."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL without the https:// prefix. Used to build the sub/aud trust conditions."
  type        = string
}

variable "permissions_boundary" {
  description = "ARN of the permissions boundary attached to the IAM role. Required when a PlatformEngineer applies - that permission set only allows creating roles that carry the engineer boundary. null when an admin/CI applies."
  type        = string
  default     = null
}

variable "namespace" {
  description = "Namespace Velero runs in. Half of the IRSA trust condition's service-account subject."
  type        = string
  default     = "velero"
}

variable "service_account" {
  description = "ServiceAccount Velero runs as. Must match serviceAccount.server.name in the gitops-flux HelmRelease - the vmware-tanzu chart creates one ServiceAccount, shared by the server deployment and the backup/restore/schedule CLI jobs it spawns."
  type        = string
  default     = "velero"
}

variable "bucket_name" {
  description = "Name of the S3 bucket Velero writes backup manifests and object metadata to. Must be globally unique."
  type        = string
}

variable "backup_retention_days" {
  description = "Days before a backup's objects are expired out of the bucket by lifecycle rule. This is a floor under whatever TTL a Velero Schedule sets - if a Schedule's ttl outlives this, the bucket deletes the objects out from under Velero's own retention bookkeeping. Keep this at or above the longest Schedule ttl in gitops-flux."
  type        = number
  default     = 90
}
