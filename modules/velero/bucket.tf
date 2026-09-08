###############################################################################
# Backup bucket. Holds Velero's object-storage half of a backup - resource
# YAML, restic/kopia data if file-level backup is ever turned on, and the
# per-backup metadata Velero reads to list/describe/restore. The EBS-snapshot
# half of a backup lives entirely in EC2, not here (see iam.tf).
###############################################################################

resource "aws_s3_bucket" "velero" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Floor under Velero's own Schedule ttl, not a substitute for it. Velero is
# still the thing that decides a backup is expired and deletes its manifest;
# this rule only guarantees the bucket doesn't quietly outlive that decision
# forever if a Schedule's ttl is ever raised without raising this too.
resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    # Required as of provider 5.x even when it's a no-op: a rule with no
    # prefix/filter applies to every object, but the schema now insists you
    # say so explicitly rather than inferring it from absence. Omitting this
    # still plans clean today - AWS just deprecated the inference and warns
    # on it - but it becomes a hard error on a future provider bump.
    filter {}

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket = aws_s3_bucket.velero.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}
