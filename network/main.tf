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

###############################################################################
# Configuration comes from the shared ../config.yaml: the `common` section
# merged with this layer's `network` section. account_id is deliberately NOT in
# that file - it is committed and this repository is public - so it stays a
# variable fed by the gitignored terraform.tfvars.
#
# variables.tf and terraform.tfvars still carry the old inputs. They are unused
# while the locals below are in place, and are kept so this can be reverted by
# reverting this file alone.
###############################################################################

locals {
  config_file = yamldecode(file("${path.module}/../config.yaml"))
  config      = merge(local.config_file.common, local.config_file.network)

  name = "${local.config.org_prefix}-shared"
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

module "vpc" {
  source = "../modules/vpc"

  name       = local.name
  cidr_block = local.config.vpc_cidr

  # Two public subnets (ADR 0006). The module takes the zones from this
  # provider's region rather than naming them, so nothing pins us to us-east-1.
  az_count = local.config.az_count

  enable_dns_support   = local.config.enable_dns_support
  enable_dns_hostnames = local.config.enable_dns_hostnames
  instance_tenancy     = local.config.instance_tenancy

  create_internet_gateway = local.config.create_internet_gateway
  map_public_ip_on_launch = local.config.map_public_ip_on_launch
  extra_routes            = local.config.extra_routes

  # Free, and keeps ECR image-layer pulls (stored in S3) off the public path.
  enable_s3_gateway_endpoint = local.config.enable_s3_gateway_endpoint

  # Lets the AWS Load Balancer Controller discover these subnets for public ELBs.
  subnet_tags = local.config.subnet_tags
}

###############################################################################
# Publish outputs for downstream layers (eks) to read from SSM, so they need no
# access to this layer's state. State strategy: "published parameters".
###############################################################################

resource "aws_ssm_parameter" "vpc_id" {
  name  = "/${local.config.org_prefix}/shared/network/vpc_id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name  = "/${local.config.org_prefix}/shared/network/public_subnet_ids"
  type  = "StringList"
  value = join(",", module.vpc.public_subnet_ids)
}
