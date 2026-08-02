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

  # Added after the first local apply, then migrated with:
  #   terraform init -migrate-state
  backend "s3" {
    bucket       = "u25c-tfstate-808540602855"
    key          = "shared/bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:808540602855:key/cee2883d-7322-41b3-bd0c-f71e1effe89f"
    use_lockfile = true
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

  # An organisation trail belongs to the MANAGEMENT account even when a
  # delegated administrator creates it, so the SourceArn CloudTrail presents to
  # S3 and KMS is in that account. Both are listed because the trail is an
  # account-level trail until organization_id is set, and the account-level ARN
  # must keep working while it is.
  trail_owner_account_ids = compact([
    var.account_id,
    var.organization_management_account_id,
  ])

  trail_arns = [
    for a in local.trail_owner_account_ids :
    "arn:${data.aws_partition.current.partition}:cloudtrail:${var.region}:${a}:trail/${local.trail}"
  ]

  # An organisation trail encrypts log files ON BEHALF OF every member account,
  # so each one needs to appear in the KMS encryption context. Listing only the
  # trail owner works for an account-level trail and silently stops working the
  # moment the trail goes organisation-wide.
  trail_encryption_account_ids = distinct(concat(
    local.trail_owner_account_ids,
    var.organization_id == "" ? [] : var.organization_member_account_ids,
  ))
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
        # kms:Decrypt is not optional here. The trail bucket has
        # bucket_key_enabled, and AWS requires kms:Decrypt to create or update a
        # trail with SSE-KMS against a bucket using an S3 Bucket Key. Without it
        # CreateTrail fails with InsufficientEncryptionPolicyException, which
        # names the bucket and the key and says nothing about which one.
        Action   = ["kms:GenerateDataKey*", "kms:DescribeKey", "kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = [
              for a in local.trail_encryption_account_ids :
              "arn:${data.aws_partition.current.partition}:cloudtrail:*:${a}:trail/*"
            ]
          }
        }
      },
      {
        Sid    = "AllowStateReaderAccounts"
        Effect = "Allow"
        Principal = {
          AWS = [for a in var.state_reader_account_ids :
          "arn:${data.aws_partition.current.partition}:iam::${a}:root"]
        }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = "*"
      },
      {
        # S3 server access logging writes into a CMK-encrypted bucket.
        Sid       = "AllowS3LogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.account_id }
        }
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${var.region}:${var.account_id}:log-group:*"
          }
        }
      }
    ]
  })
}

###############################################################################
# Access log bucket - the destination for S3 server access logging
###############################################################################

# The access-log bucket cannot log its own access without generating an infinite
# feedback loop of log entries, which AWS explicitly warns against. Access to this
# bucket is instead covered by CloudTrail S3 data events.
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "access_logs" {
  bucket = "${var.org_prefix}-s3-access-logs-${var.account_id}"
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.platform.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket     = aws_s3_bucket.access_logs.id
  depends_on = [aws_s3_bucket_versioning.access_logs]
  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "S3ServerAccessLogsPolicy"
      Effect    = "Allow"
      Principal = { Service = "logging.s3.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.access_logs.arn}/*"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
      }
    }]
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

resource "aws_s3_bucket_logging" "tfstate" {
  bucket        = aws_s3_bucket.tfstate.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "tfstate/"
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }],
      # The budgets configuration runs in the management account (Organizations,
      # SCPs and budget actions only exist there) but keeps its state in this
      # bucket, so there is one state backend rather than two.
      length(var.state_reader_account_ids) == 0 ? [] : [{
        Sid    = "AllowManagementAccountState"
        Effect = "Allow"
        Principal = {
          AWS = [for a in var.state_reader_account_ids :
          "arn:${data.aws_partition.current.partition}:iam::${a}:root"]
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      }]
    )
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

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.platform.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "cloudtrail" {
  bucket        = aws_s3_bucket.cloudtrail.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "cloudtrail/"
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
            "aws:SourceArn" = local.trail_arns
          }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        # An organisation trail writes member-account logs under the ORG id, not
        # under each account id. Without the second prefix the trail turns on,
        # reports healthy, and silently delivers nothing for every account except
        # this one.
        Resource = compact([
          "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.account_id}/*",
          var.organization_id == "" ? "" : "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.organization_id}/*",
        ])
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arns
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${local.name}"
  retention_in_days = var.cloudwatch_retention_days
  kms_key_id        = aws_kms_key.platform.arn
}

data "aws_iam_policy_document" "cloudtrail_cw_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    # Both owners, for the same reason the bucket policy lists both trail ARNs.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = local.trail_owner_account_ids
    }
  }
}

resource "aws_iam_role" "cloudtrail_cw" {
  name               = "${local.name}-cloudtrail-cloudwatch"
  description        = "Lets CloudTrail deliver events to CloudWatch Logs"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_cw_trust.json
}

resource "aws_iam_role_policy" "cloudtrail_cw" {
  name = "deliver-to-cloudwatch"
  role = aws_iam_role.cloudtrail_cw.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# Logs go to S3 for durable retention AND to CloudWatch, where a metric filter
# can alarm on events in near real time. S3 alone gives you forensics after the
# fact; CloudWatch is what lets you notice while it is happening.
#
# As an ORGANISATION trail it also captures Staging, Prod and the management
# account, into this bucket, with no per-account setup and no extra cost - AWS
# bills the first copy of management events at zero. A member account cannot turn
# it off or exclude itself, which is the property that makes it evidence.
#
# Requires, in the management account: cloudtrail.amazonaws.com enabled for
# organisation access, and this account registered as delegated administrator.
# ../organization does both.
resource "aws_cloudtrail" "main" {
  name                          = local.trail
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = var.organization_id != ""
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.platform.arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cw.arn

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_iam_role_policy.cloudtrail_cw,
  ]
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
