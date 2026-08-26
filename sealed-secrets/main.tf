###############################################################################
# sealed-secrets layer - the AWS-side backup destination for the sealed-secrets
# controller's encryption key(s). State key shared/sealed-secrets, isolated
# from every other layer.
#
# This layer creates the empty Secrets Manager container only. Terraform never
# holds the key material itself - that would put the highest-consequence
# secret on the platform inside a state file. The actual backup (extracting
# the key(s) from the cluster and writing them here) is a manual step - see
# ops-program/runbooks (ops-program#19).
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
    key          = "shared/sealed-secrets/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:808540602855:key/cee2883d-7322-41b3-bd0c-f71e1effe89f"
    use_lockfile = true
  }
}

locals {
  config = yamldecode(file("${path.module}/../config.yaml")).common
}

provider "aws" {
  region              = local.config.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Org        = local.config.org_prefix
      Env        = "shared"
      Workstream = "utils"
      ManagedBy  = "terraform"
      Repo       = "infra-aws"
    }
  }
}

# The same KMS key bootstrap already created for Terraform state and
# CloudTrail. Looked up by alias rather than shared state - same "no
# cross-layer state reads" seam the cert-manager and karpenter layers use.
data "aws_kms_alias" "platform" {
  name = "alias/${local.config.org_prefix}-shared-platform"
}

# The container only. Empty until the manual backup procedure puts the
# controller's key(s) in as the secret value.
resource "aws_secretsmanager_secret" "sealed_secrets_controller_keys" {
  name        = "u25c/shared/sealed-secrets/controller-keys"
  description = "Backup of the sealed-secrets controller's RSA keypair(s). See ops-program/docs/secret-management.md."
  kms_key_id  = data.aws_kms_alias.platform.target_key_id

  # Default 30-day recovery window: an accidental `terraform destroy` here is
  # recoverable, not catastrophic. The unrecoverable failure mode is losing
  # the key material inside, not the container.
}