###############################################################################
# dev environment root - version constraints and state backend.
#
# Environment-based layout under roots/environments/. This dev root is the only
# environment deployed; staging/ and prod/ stay dormant (ADR 0003). The root
# calls ../../../modules/vpc to build the network.
#
# State key is scoped to the environment (dev/), matching this folder. Same
# bucket as every other layer - only the key differs. The terraform.tfstate
# object is created here on first apply.
###############################################################################

terraform {
  required_version = ">= 1.10" # floor, not a pin; native S3 locking needs >= 1.10

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70" # minor/patch float, major pinned
    }
  }

  backend "s3" {
    bucket       = "u25c-tfstate-808540602855"
    key          = "dev/network/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:808540602855:key/cee2883d-7322-41b3-bd0c-f71e1effe89f"
    use_lockfile = true # native S3 locking - no DynamoDB table (the repo forbids one)
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id] # fail fast if pointed at the wrong account

  # Applied automatically to every resource this root creates - including those
  # inside the vpc module, which inherits this provider.
  default_tags {
    tags = {
      Org        = "u25c"
      Env        = "dev"
      Workstream = "infra"
      ManagedBy  = "terraform"
      Repo       = "infra-aws"
    }
  }
}
