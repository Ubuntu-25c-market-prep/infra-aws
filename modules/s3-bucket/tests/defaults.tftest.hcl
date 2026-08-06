###############################################################################
# The module's whole premise is that its posture cannot be turned off. These
# tests are what stops that premise decaying into a comment.
#
# Plan-mode only: no AWS calls, no credentials, no cost. Run with
#
#   terraform -chdir=modules/s3-bucket init
#   terraform -chdir=modules/s3-bucket test
###############################################################################

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  name        = "u25c-example-bucket-000000000000"
  kms_key_arn = "arn:aws:kms:us-east-1:000000000000:key/00000000-0000-0000-0000-000000000000"
}

run "defaults_are_locked_down" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "Public access block must be fully on. This module must not be able to produce a public bucket."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must be BucketOwnerEnforced, which disables ACLs."
  }

  # `rule` here is a set, not a list, so it has no addressable index - one()
  # unwraps the single element and fails loudly if a second ever appears.
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Encryption must be aws:kms, not SSE-S3."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).kms_master_key_id == var.kms_key_arn
    error_message = "Encryption must use the KMS key the caller passed."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled
    error_message = "bucket_key_enabled must stay on - without it KMS is billed per object operation."
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 0
    error_message = "Access logging must be absent when log_bucket is empty."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must default to false."
  }
}

run "access_logging_when_a_target_is_given" {
  command = plan

  variables {
    log_bucket = "u25c-s3-access-logs-000000000000"
    log_prefix = "example/"
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 1
    error_message = "Access logging must be configured when log_bucket is set."
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_bucket == "u25c-s3-access-logs-000000000000"
    error_message = "Access logs must go to the bucket the caller named."
  }
}

# Exercises the dynamic expiration block, which renders nothing when the default
# null is left in place.
run "current_version_expiry_is_optional" {
  command = plan

  variables {
    expiration_days = 30
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == var.name
    error_message = "Plan must succeed with expiration_days set."
  }
}

run "rejects_a_name_s3_would_refuse" {
  command = plan

  variables {
    name = "U25C-Not-A-Valid-Bucket-Name"
  }

  expect_failures = [var.name]
}
