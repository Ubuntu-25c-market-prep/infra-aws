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

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Org        = "u25c"
      Env        = "shared"
      Workstream = "infra"
      ManagedBy  = "terraform"
      Repo       = "infra-aws"
    }
  }
}

###############################################################################
# Read the VPC values the network layer published to SSM. This is the seam
# between the two state files - no remote_state, no shared state access.
###############################################################################

data "aws_ssm_parameter" "vpc_id" {
  name = "/u25c/shared/network/vpc_id"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/u25c/shared/network/public_subnet_ids"
}

module "eks" {
  source = "../modules/eks"

  cluster_name = "u25c-shared"
  vpc_id       = data.aws_ssm_parameter.vpc_id.value
  subnet_ids   = split(",", data.aws_ssm_parameter.public_subnet_ids.value)

  kubernetes_version = var.kubernetes_version
  instance_types     = var.node_instance_types
  desired_size       = var.node_desired_size
  min_size           = var.node_min_size
  max_size           = var.node_max_size

  # A PlatformEngineer may only create IAM roles that carry the engineer
  # boundary (identity/main.tf). Without this the apply fails with
  # AccessDenied on iam:CreateRole.
  permissions_boundary = "arn:aws:iam::${var.account_id}:policy/u25c-engineer-boundary"

  # authentication_mode is API, so cluster access comes only from these entries.
  admin_principal_arns = var.admin_principal_arns
}
