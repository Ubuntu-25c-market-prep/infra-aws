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
    key          = "shared/thanos/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:808540602855:key/cee2883d-7322-41b3-bd0c-f71e1effe89f"
    use_lockfile = true
  }
}

locals {
  config = yamldecode(file("${path.module}/../config.yaml")).common
  layer  = yamldecode(file("${path.module}/config.yaml")).thanos

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
      Workstream = "monitoring"
      ManagedBy  = "terraform"
      Repo       = "infra-aws"
    }
  }
}

###############################################################################
# S3 bucket for Thanos metric blocks
###############################################################################

resource "aws_s3_bucket" "thanos" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_versioning" "thanos" {
  bucket = aws_s3_bucket.thanos.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "thanos" {
  bucket = aws_s3_bucket.thanos.id

  rule {
    id     = "expire-old-metrics"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "thanos" {
  bucket = aws_s3_bucket.thanos.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "thanos" {
  bucket = aws_s3_bucket.thanos.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

###############################################################################
# IRSA role — lets the Thanos sidecar (running as the Prometheus SA) access S3
###############################################################################

data "aws_partition" "current" {}

data "aws_eks_cluster" "this" {
  name = local.name
}

locals {
  oidc_issuer_url   = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:oidc-provider/${local.oidc_issuer_url}"
}

data "aws_iam_policy_document" "thanos_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_url}:sub"
      values   = ["system:serviceaccount:${local.layer.namespace}:${local.layer.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "thanos_s3" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.thanos.arn,
      "${aws_s3_bucket.thanos.arn}/*",
    ]
  }
}

resource "aws_iam_role" "thanos" {
  name                 = "${local.name}-thanos"
  assume_role_policy   = data.aws_iam_policy_document.thanos_trust.json
  permissions_boundary = "arn:aws:iam::${var.account_id}:policy/${local.config.org_prefix}-engineer-boundary"
}

resource "aws_iam_role_policy" "thanos_s3" {
  name   = "thanos-s3-access"
  role   = aws_iam_role.thanos.id
  policy = data.aws_iam_policy_document.thanos_s3.json
}
