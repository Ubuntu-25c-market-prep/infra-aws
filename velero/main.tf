###############################################################################
# Velero layer - the AWS-side prerequisites for cluster backup/restore: the
# backup bucket and Velero's IRSA role. State key shared/velero, separate from
# every other layer. The in-cluster install (HelmRelease, Schedules,
# BackupStorageLocation, VolumeSnapshotLocation) lives in gitops-flux and
# consumes the outputs below.
#
# This layer reads no other layer's state. The cluster's OIDC issuer is read
# live from the cluster - the same "seam without shared state" idea the
# karpenter, cert-manager, external-dns and keda layers use.
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
    key          = "shared/velero/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:808540602855:key/cee2883d-7322-41b3-bd0c-f71e1effe89f"
    use_lockfile = true
  }
}

###############################################################################
# Configuration: the shared ../config.yaml `common` section (region,
# org_prefix) plus this layer's own config.yaml (namespace, service account,
# bucket suffix, retention). account_id stays a variable - it carries the
# account id and this repository is public - fed by ../.env locally and
# TF_VAR_account_id in CI.
###############################################################################

locals {
  config = yamldecode(file("${path.module}/../config.yaml")).common
  layer  = yamldecode(file("${path.module}/config.yaml")).velero

  name        = "${local.config.org_prefix}-shared"
  bucket_name = "${local.config.org_prefix}-shared-${local.layer.bucket_suffix}"
}

provider "aws" {
  region              = local.config.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Org        = local.config.org_prefix
      Env        = "shared"
      Workstream = "velero"
      ManagedBy  = "terraform"
      Repo       = "infra-aws"
    }
  }
}

###############################################################################
# Read the cluster's OIDC issuer. An intrinsic fact looked up live rather than
# passed between layers.
###############################################################################

data "aws_partition" "current" {}

data "aws_eks_cluster" "this" {
  name = local.name
}

locals {
  oidc_issuer_url   = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:oidc-provider/${local.oidc_issuer_url}"
}

module "velero" {
  source = "../modules/velero"

  cluster_name = local.name

  oidc_provider_arn = local.oidc_provider_arn
  oidc_provider_url = local.oidc_issuer_url

  # Same boundary the eks, karpenter, cert-manager, external-dns and keda
  # roles carry - a PlatformEngineer may only create IAM roles that carry the
  # engineer boundary.
  permissions_boundary = "arn:aws:iam::${var.account_id}:policy/${local.config.org_prefix}-engineer-boundary"

  namespace             = local.layer.namespace
  service_account       = local.layer.service_account
  bucket_name           = local.bucket_name
  backup_retention_days = local.layer.backup_retention_days
}
