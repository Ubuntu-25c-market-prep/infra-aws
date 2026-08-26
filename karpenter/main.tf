###############################################################################
# Karpenter layer - the AWS-side prerequisites for Karpenter. State key
# shared/karpenter, separate from the eks layer. The in-cluster install (Helm
# release, NodePool, EC2NodeClass) lives in gitops-flux and consumes the outputs
# below.
#
# This layer reads no other layer's state. The cluster's OIDC provider, security
# groups and subnets are read live from the cluster itself (data.aws_eks_cluster
# + a security-group lookup), the same "seam without shared state" idea the eks
# layer uses when it reads the VPC from SSM. Nothing here writes to eks/.
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
    key          = "shared/karpenter/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:808540602855:key/cee2883d-7322-41b3-bd0c-f71e1effe89f"
    use_lockfile = true
  }
}

###############################################################################
# Configuration: the shared ../config.yaml `common` section (region,
# org_prefix). This layer has no tunables of its own, so it does not carry a
# layer config.yaml. account_id stays a variable - it carries the account id and
# this repository is public - fed by ../.env locally and TF_VAR_account_id in CI.
###############################################################################

locals {
  config = yamldecode(file("${path.module}/../config.yaml")).common

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
# Read the cluster's own attributes. DescribeCluster gives the OIDC issuer, the
# EKS-managed cluster security group and the subnets the cluster runs in - all
# intrinsic to the cluster, no cross-layer state. The node security group is a
# custom SG the eks module creates; it is looked up by its Name tag.
###############################################################################

data "aws_partition" "current" {}

data "aws_eks_cluster" "this" {
  name = local.name
}

data "aws_security_group" "node" {
  filter {
    name   = "vpc-id"
    values = [data.aws_eks_cluster.this.vpc_config[0].vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = ["${local.name}-node"]
  }
}

locals {
  # IRSA trust wants the issuer without the scheme, and the OIDC provider ARN is
  # derived from it - the provider was created by the eks module, so we build its
  # ARN rather than look it up (avoids iam:ListOpenIDConnectProviders).
  oidc_issuer_url   = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:oidc-provider/${local.oidc_issuer_url}"
}

module "karpenter" {
  source = "../modules/karpenter"

  cluster_name = local.name
  region       = local.config.region
  account_id   = var.account_id

  oidc_provider_arn = local.oidc_provider_arn
  oidc_provider_url = local.oidc_issuer_url

  # Same boundary the eks module's roles carry - a PlatformEngineer may only
  # create IAM roles that carry the engineer boundary.
  permissions_boundary = "arn:aws:iam::${var.account_id}:policy/${local.config.org_prefix}-engineer-boundary"

  subnet_ids                = tolist(data.aws_eks_cluster.this.vpc_config[0].subnet_ids)
  node_security_group_id    = data.aws_security_group.node.id
  cluster_security_group_id = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

###############################################################################
# EC2 Spot service-linked role.
#
# Spot capacity is requested through CreateFleet, which requires the account to
# hold AWSServiceRoleForEC2Spot. AWS creates that role automatically on the
# first spot launch, but only when the calling principal has
# iam:CreateServiceLinkedRole - and the Karpenter controller role deliberately
# does not. Without the role every spot launch fails:
#
#   AuthFailure.ServiceLinkedRoleCreationNotPermitted: The provided credentials
#   do not have permission to create the service-linked role for EC2 Spot
#   Instances.
#
# Karpenter reads that as UnfulfillableCapacity and falls back to on-demand, so
# the spot-first NodePools in gitops-flux silently buy nothing - and because
# consolidation keeps retrying, it produces a failed CreateFleet every few
# minutes rather than one visible error.
#
# ACCOUNT-WIDE SINGLETON, not a per-cluster resource. It lives in this layer
# because Karpenter is the only thing in this account that requests spot, but a
# second cluster must NOT declare it again - the apply would fail with
# InvalidInput / role already exists. If it ever gets created by hand, import it
# rather than recreating it:
#
#   terraform import aws_iam_service_linked_role.spot \
#     arn:aws:iam::<account_id>:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot
#
# No permissions_boundary here, unlike the roles in modules/karpenter: AWS does
# not accept a boundary on a service-linked role. Deletion is also safe by
# construction - AWS refuses to remove the role while spot instances still
# depend on it, so a layer destroy fails loudly instead of stranding capacity.
###############################################################################

resource "aws_iam_service_linked_role" "spot" {
  aws_service_name = "spot.amazonaws.com"
  description      = "Lets EC2 Spot launch and manage spot instances for Karpenter."
}
