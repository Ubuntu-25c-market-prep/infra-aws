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

###############################################################################
# Configuration comes from two files: `common` in the repo-root ../config.yaml,
# shared by every layer, overlaid with this layer's own ./config.yaml. A key in
# the layer file wins over the same key in common.
#
# account_id is deliberately in NEITHER - both are committed and this repository
# is public - so it stays a variable, fed by the gitignored ../.env locally and
# by a GitHub variable in CI.
###############################################################################

locals {
  config = merge(
    yamldecode(file("${path.module}/../config.yaml")).common,
    yamldecode(file("${path.module}/config.yaml")).ecr,
  )
}

provider "aws" {
  region              = local.config.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Org        = local.config.org_prefix
      Env        = "shared"
      Workstream = "infra"
      ManagedBy  = "terraform"
      Repo       = "infra-aws"
    }
  }
}

module "ecr" {
  source = "../modules/ecr"

  # The registry namespace: repositories are created as <name_prefix>/<image>.
  # Its own key, not org_prefix - see the note in config.yaml.
  name_prefix  = local.config.name_prefix
  repositories = local.config.repositories

  untagged_expire_days = local.config.untagged_expire_days
}
