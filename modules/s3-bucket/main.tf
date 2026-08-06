###############################################################################
# A private, encrypted, versioned S3 bucket - and nothing else.
#
# READ THIS BEFORE ADDING A VARIABLE.
#
# The security posture below is deliberately NOT configurable. Public access
# block, BucketOwnerEnforced ownership, KMS encryption, versioning and the
# TLS-only policy are hardcoded, so no caller can turn them off and no reviewer
# has to check whether one did.
#
# Not because a switch would hide - tfvars is committed and reviewed now - but
# because the review would have to catch it. A variable that can make a bucket
# public turns "is this bucket private?" into a question with a per-caller
# answer, checked by whoever happens to read that pull request. Hardcoded, it
# has one answer for every caller, and changing it means editing this file,
# which CODEOWNERS routes to @infra.
#
# If you need a bucket that is genuinely public - a CloudFront origin, a static
# site - do not add a switch here. Write a second module whose name says so.
###############################################################################

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    # Cuts KMS request cost by reusing a data key per bucket rather than calling
    # Decrypt once per object.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs off entirely. Object ownership is the bucket owner's, always, which is
# what makes cross-account writes land as objects this account can actually read.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # The API rejects a lifecycle configuration on a bucket whose versioning state
  # is still settling.
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "baseline"
    status = "Enabled"

    # An empty filter means "every object". Omitting the block entirely is a
    # provider-level error on aws ~> 5.
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_expiration_days
    }

    dynamic "expiration" {
      for_each = var.expiration_days == null ? [] : [var.expiration_days]

      content {
        days = expiration.value
      }
    }
  }
}

resource "aws_s3_bucket_logging" "this" {
  count = var.log_bucket == "" ? 0 : 1

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.log_bucket
  target_prefix = var.log_prefix
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  # Ordering, not correctness: BlockPublicPolicy only rejects policies that GRANT
  # public access, and this one denies. Attaching after the block still removes
  # any window in which the bucket exists with neither.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
