###############################################################################
# cert-manager layer - the AWS-side prerequisites for cert-manager's Route 53
# DNS-01 solver. State key shared/cert-manager, separate from the eks and
# karpenter layers. The in-cluster install (HelmRelease, ClusterIssuer,
# Certificate) lives in gitops-flux and consumes the role ARN output below.
#
# This layer reads no other layer's state. The cluster's OIDC issuer is read
# live from the cluster and the hosted zone is looked up by name - the same
# "seam without shared state" idea the karpenter layer uses.
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
    key          = "shared/cert-manager/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:808540602855:key/cee2883d-7322-41b3-bd0c-f71e1effe89f"
    use_lockfile = true
  }
}

###############################################################################
# Configuration: the shared ../config.yaml `common` section (region,
# org_prefix) plus this layer's own config.yaml (hosted zone, service account).
# account_id stays a variable - it carries the account id and this repository
# is public - fed by ../.env locally and TF_VAR_account_id in CI.
###############################################################################

locals {
  config = yamldecode(file("${path.module}/../config.yaml")).common
  layer  = yamldecode(file("${path.module}/config.yaml")).cert_manager

  name = "${local.config.org_prefix}-shared"
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

###############################################################################
# Read the cluster's OIDC issuer and the hosted zone. Both are intrinsic facts
# looked up live rather than passed between layers.
###############################################################################

data "aws_partition" "current" {}

data "aws_eks_cluster" "this" {
  name = local.name
}

data "aws_route53_zone" "this" {
  name         = local.layer.hosted_zone_name
  private_zone = false
}

locals {
  # IRSA trust wants the issuer without the scheme, and the OIDC provider ARN is
  # derived from it - the provider was created by the eks module, so we build its
  # ARN rather than look it up (avoids iam:ListOpenIDConnectProviders).
  oidc_issuer_url   = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:oidc-provider/${local.oidc_issuer_url}"
}

module "cert_manager" {
  source = "../modules/cert-manager"

  cluster_name = local.name

  oidc_provider_arn = local.oidc_provider_arn
  oidc_provider_url = local.oidc_issuer_url

  # Same boundary the eks and karpenter roles carry - a PlatformEngineer may
  # only create IAM roles that carry the engineer boundary.
  permissions_boundary = "arn:aws:iam::${var.account_id}:policy/${local.config.org_prefix}-engineer-boundary"

  hosted_zone_id  = data.aws_route53_zone.this.zone_id
  namespace       = local.layer.namespace
  service_account = local.layer.service_account
}