###############################################################################
# Smallest useful call of ../../. Must plan cleanly - see modules/README.md.
#
# Access logging is left off here because the example has no log bucket to point
# at. Real callers pass log_bucket; see storage/main.tf.
###############################################################################

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  region = var.region
}

module "bucket" {
  source = "../.."

  name        = var.name
  kms_key_arn = var.kms_key_arn
}

output "bucket_arn" {
  description = "ARN of the bucket the example created."
  value       = module.bucket.arn
}
