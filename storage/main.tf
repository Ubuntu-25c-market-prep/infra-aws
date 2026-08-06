###############################################################################
# Object storage for the platform.
#
# One bucket today. Add the next one as another module block rather than a
# for_each over a map: an explicit block is a reviewable diff, and a renamed map
# key silently destroys and recreates the bucket it used to name.
#
# Bucket definitions belong in THIS file, never in terraform.tfvars - tfvars is
# gitignored and CI rebuilds it from a secret, so anything declared there is
# invisible to review and needs a secret rotation to change.
#
# Depends on ../bootstrap for the KMS key and the access-log bucket. Costs
# essentially nothing until objects land in it.
###############################################################################

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Org        = var.org_prefix
      Env        = "shared"
      Workstream = "platform"
      ManagedBy  = "terraform"
      Repo       = "infra-aws"
    }
  }
}

locals {
  name = "${var.org_prefix}-shared"

  # Created by ../bootstrap in this account. Constructed rather than read from
  # remote state, matching how ../identity references the boundary that ../iam
  # creates - the name is deterministic and the coupling is not worth a data
  # source.
  log_bucket = "${var.org_prefix}-s3-access-logs-${var.account_id}"
}

###############################################################################
# Application data
#
# The account id suffix is not decoration. S3 bucket names are globally unique
# across every AWS customer, so "u25c-shared-app-data" is a name someone else may
# already hold, and the failure arrives at apply time as BucketAlreadyExists.
# Every bucket in ../bootstrap carries the same suffix for the same reason.
#
# No expiration_days: this holds data the platform did not generate and cannot
# regenerate. Noncurrent versions are cleaned up after 90 days.
###############################################################################

module "app_data" {
  source = "../modules/s3-bucket"

  name        = "${local.name}-app-data-${var.account_id}"
  kms_key_arn = var.kms_key_arn
  log_bucket  = local.log_bucket
  log_prefix  = "app-data/"
}
