###############################################################################
# Registry layer - ECR. State key shared/ecr (state strategy layer 8).
#
# Deliberately NOT per environment. An image is built once and the same digest
# is promoted dev -> staging -> prod; a registry per environment would mean
# rebuilding per environment, and then prod runs a binary nobody tested. One
# registry, many tags.
#
# Separate state from eks/ because the two have nothing to say to each other:
# the node role's pull permission is an AWS-managed policy attached in
# modules/eks, and a Kubernetes image reference is just a string.
###############################################################################

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  backend "s3" {
    bucket       = "u25c-tfstate-808540602855"
    key          = "shared/ecr/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:808540602855:key/cee2883d-7322-41b3-bd0c-f71e1effe89f"
    use_lockfile = true
  }
}

provider "aws" {
  region              = var.region
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

module "ecr" {
  source = "../modules/ecr"

  name_prefix  = var.org_prefix
  repositories = var.repositories

  untagged_expire_days = var.untagged_expire_days
  max_image_count      = var.max_image_count
}
