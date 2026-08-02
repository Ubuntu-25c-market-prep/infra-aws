###############################################################################
# GitHub Actions -> AWS via OIDC. No static access keys anywhere.
#
# Two roles, deliberately asymmetric:
#   plan  - read-only, assumable from pull requests in any infrastructure repo
#   apply - mutating, assumable ONLY from refs/heads/main in infra-aws
#
# The asymmetry is the point. A pull request from a fork or a feature branch can
# render a plan but cannot change the account.
###############################################################################

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Populated after bootstrap. See ../README.md.
  backend "s3" {}
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Org        = var.org_prefix
      Env        = "shared"
      Workstream = "security"
      ManagedBy  = "terraform"
      Repo       = "infra-aws"
    }
  }
}

data "aws_partition" "current" {}

locals {
  name = "${var.org_prefix}-shared"

  # Every repository that may render a plan.
  plan_repos = [
    "infra-aws",
    "infra-modules",
    "platform-addons",
    "platform-observability",
    "platform-security",
    "gitops-flux",
    "gitops-argocd",
  ]

  oidc_arn = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

###############################################################################
# OIDC provider
###############################################################################

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS validates GitHub's certificate chain natively; a pinned thumbprint is no
  # longer required and became an outage source when GitHub rotated its CA.
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]

  lifecycle {
    ignore_changes = [thumbprint_list]
  }
}

###############################################################################
# Plan role - read only, any pull request in the listed repositories
###############################################################################

data "aws_iam_policy_document" "plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to this organisation's repositories only. Without this condition any
    # GitHub Actions workflow on the internet could assume the role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for r in local.plan_repos : "repo:${var.github_org}/${r}:*"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${local.name}-gha-plan"
  description          = "Read-only role for Terraform plan from GitHub Actions"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess cannot write the state lock file, which `terraform plan` needs.
data "aws_iam_policy_document" "plan_state" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.state_bucket}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "state-access"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

###############################################################################
# Apply role - mutating, only from main in infra-aws
###############################################################################

data "aws_iam_policy_document" "apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Exact match, not StringLike. Only the protected default branch of the
    # infrastructure repository, and only through the named environment.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/infra-aws:ref:refs/heads/main",
        "repo:${var.github_org}/infra-aws:environment:aws-apply",
      ]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "${local.name}-gha-apply"
  description          = "Terraform apply from the protected branch of infra-aws"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}

# Administrator minus the actions that would remove the safety rails or destroy
# state. CI has no legitimate reason to do any of these.
data "aws_iam_policy_document" "apply_guardrails" {
  statement {
    sid    = "ProtectAuditAndState"
    effect = "Deny"
    actions = [
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
      "organizations:LeaveOrganization",
      "account:CloseAccount",
      "iam:DeleteAccountPasswordPolicy",
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "NoLongLivedCredentials"
    effect    = "Deny"
    actions   = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_guardrails.json
}
