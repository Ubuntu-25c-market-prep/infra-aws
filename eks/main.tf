###############################################################################
# Cluster layer - EKS. State key shared/eks (state strategy layer 7). Separate
# state from the network layer; the VPC's values are read from SSM, so this
# layer needs no access to the network layer's state.
###############################################################################

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket       = "u25c-tfstate-808540602855"
    key          = "shared/eks/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:808540602855:key/cee2883d-7322-41b3-bd0c-f71e1effe89f"
    use_lockfile = true
  }
}

###############################################################################
# Configuration comes from the shared ../config.yaml: the `common` section
# merged with this layer's `eks` section. account_id and admin_principal_arns
# are deliberately NOT in that file - it is committed and this repository is
# public, and both embed the account id - so they stay variables fed by the
# gitignored terraform.tfvars.
#
# variables.tf and terraform.tfvars still carry the old inputs. They are unused
# while the locals below are in place, and are kept so this can be reverted by
# reverting this file alone.
###############################################################################

locals {
  config_file = yamldecode(file("${path.module}/../config.yaml"))
  config      = merge(local.config_file.common, local.config_file.eks)

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

###############################################################################
# Read the VPC values the network layer published to SSM. This is the seam
# between the two state files - no remote_state, no shared state access
###############################################################################

data "aws_ssm_parameter" "vpc_id" {
  name = "/${local.config.org_prefix}/shared/network/vpc_id"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/${local.config.org_prefix}/shared/network/public_subnet_ids"
}

module "eks" {
  source = "../modules/eks"

  cluster_name = local.name
  vpc_id       = data.aws_ssm_parameter.vpc_id.value
  subnet_ids   = split(",", data.aws_ssm_parameter.public_subnet_ids.value)

  kubernetes_version = local.config.kubernetes_version
  instance_types     = local.config.node_instance_types
  desired_size       = local.config.node_desired_size
  min_size           = local.config.node_min_size
  max_size           = local.config.node_max_size

  # A PlatformEngineer may only create IAM roles that carry the engineer
  # boundary (identity/main.tf). Without this the apply fails with
  # AccessDenied on iam:CreateRole.
  permissions_boundary = "arn:aws:iam::${var.account_id}:policy/${local.config.org_prefix}-engineer-boundary"

  # authentication_mode is API, so cluster access comes only from these entries.
  #
  # Passed in rather than looked up: data.aws_iam_roles calls iam:ListRoles, and
  # the PlatformEngineer permission set carries an explicit deny on it, so the
  # lookup fails at plan time for the people who actually apply this.
  authentication_mode  = local.config.authentication_mode
  admin_principal_arns = var.admin_principal_arns
}
