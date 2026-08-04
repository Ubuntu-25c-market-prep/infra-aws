###############################################################################
# Network layer - the platform VPC. State key shared/network (state strategy
# layer 5). Single VPC shared by all environments (namespaces in one cluster).
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
    key          = "shared/network/terraform.tfstate"
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

locals {
  name = "${var.org_prefix}-shared"
}

module "vpc" {
  source = "../modules/vpc"

  name       = local.name
  cidr_block = var.vpc_cidr

  # Two public subnets (ADR 0006). The module takes the zones from this
  # provider's region rather than naming them, so nothing pins us to us-east-1.
  az_count = var.az_count

  # Free, and keeps ECR image-layer pulls (stored in S3) off the public path.
  enable_s3_gateway_endpoint = true

  # Lets the AWS Load Balancer Controller discover these subnets for public ELBs.
  subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

###############################################################################
# Publish outputs for downstream layers (eks) to read from SSM, so they need no
# access to this layer's state. State strategy: "published parameters".
###############################################################################

resource "aws_ssm_parameter" "vpc_id" {
  name  = "/${var.org_prefix}/shared/network/vpc_id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name  = "/${var.org_prefix}/shared/network/public_subnet_ids"
  type  = "StringList"
  value = join(",", module.vpc.public_subnet_ids)
}
