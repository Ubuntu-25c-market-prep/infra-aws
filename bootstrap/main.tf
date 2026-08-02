###############################################################################
# Bootstrap - the things Terraform cannot create for itself.
#
# Run this ONCE with local state, then migrate state into the bucket it creates.
# See ../README.md for the two-phase procedure.
#
# Deliberately ordered so the guardrails exist before anything can spend:
# budget and anomaly detection come up in the same apply as the state backend.
###############################################################################

terraform {
  required_version = ">= 1.10" # native S3 state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  region = var.region

  # Refuses to run against any account but the intended one. This repository is
  # public and the same code will be read by 16 people - make a wrong-account
  # apply impossible rather than unlikely.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Org        = var.org_prefix
      Env        = "shared"
      Workstream = "infra"
      ManagedBy  = "terraform"
      Repo       = "infra-aws"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name   = "${var.org_prefix}-shared"
  bucket = "${var.org_prefix}-tfstate-${var.account_id}"
  trail  = "${var.org_prefix}-cloudtrail-${var.account_id}"
}

###############################################################################
# KMS - encrypts Terraform state and CloudTrail logs
###############################################################################

resource "aws_kms_key" "platform" {
  description             = "Platform shared key: Terraform state and CloudTrail"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIAMPolicies"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudTrailEncrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:${data.aws_partition.current.partition}:cloudtrail:*:${var.account_id}:trail/*"
          }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${local.name}-platform"
  target_key_id = aws_kms_key.platform.key_id
}

###############################################################################
# Terraform state backend
###############################################################################

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket

  # State is the one thing whose loss is unrecoverable.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.platform.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket     = aws_s3_bucket.tfstate.id
  depends_on = [aws_s3_bucket_versioning.tfstate]

  rule {
    id     = "expire-noncurrent-state"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate_tls_only" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

###############################################################################
# Cost guardrails - these exist before the platform can spend anything
###############################################################################

resource "aws_budgets_budget" "monthly" {
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Warn at 50% and 80% of actual, and on a forecast to exceed. The forecast
  # notification is the one that gives you time to react.
  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.alert_emails
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_emails
  }
}

resource "aws_ce_anomaly_monitor" "services" {
  name              = "${local.name}-service-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "daily" {
  name      = "${local.name}-anomaly-daily"
  frequency = "DAILY"

  monitor_arn_list = [aws_ce_anomaly_monitor.services.arn]

  dynamic "subscriber" {
    for_each = var.alert_emails
    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }
}

###############################################################################
# Audit trail
###############################################################################

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.org_prefix}-cloudtrail-${var.account_id}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = var.cloudtrail_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudtrail:${var.region}:${var.account_id}:trail/${local.trail}"
          }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudtrail:${var.region}:${var.account_id}:trail/${local.trail}"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = local.trail
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.platform.arn

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

###############################################################################
# Account-wide baseline
###############################################################################

resource "aws_s3_account_public_access_block" "account" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "account" {
  enabled = true
}

resource "aws_iam_account_password_policy" "account" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 12
}
