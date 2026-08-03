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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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
  #
  # Four entries were removed by ADR 0010, which archived the repositories they
  # named. A subject claim for a repository that no longer exists is dead weight
  # rather than a live grant, but leaving it invites someone to recreate the name
  # and inherit the trust.
  #
  # Only infra-aws contains Terraform today. gitops-flux and gitops-argocd are
  # kept because they predate this change and removing them is a posture decision
  # rather than a consequence of the merge - worth doing, in its own pull request,
  # with @security looking at it.
  plan_repos = [
    "infra-aws",
    "gitops-flux",
    "gitops-argocd",
  ]

  oidc_arn = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"

  # This organisation issues OIDC tokens in GitHub's IMMUTABLE ID format, so the
  # sub claim is not `repo:<org>/<repo>:<context>` but:
  #
  #   repo:Ubuntu-25c-market-prep@311938159/infra-aws@1319733777:pull_request
  #
  # A trust policy written against the documented plain format matches nothing
  # and fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity` - an
  # authorization error that points you at the trust policy's *contents* rather
  # than its shape. If you ever need to see the real claim, it is the userName
  # field of the failed event in CloudTrail.
  #
  # The org id is pinned because that is the property worth pinning: an attacker
  # who creates an organisation named Ubuntu-25c-market-prep after a rename
  # cannot reuse the id. Repo ids are wildcarded so a repo created later works
  # without a lookup - repository names cannot contain "@", so `infra-aws@*`
  # cannot match anything but this repo's id.
  org_subject_prefix = "repo:${var.github_org}@${var.github_org_id}"
}

###############################################################################
# OIDC provider
###############################################################################

# Read at plan time rather than pinned. A hardcoded thumbprint becomes an outage
# the day GitHub rotates its CA; the placeholder it replaced relied on AWS
# ignoring the value entirely, which is true but undocumented enough to be worth
# not depending on. This was not the cause of any failure - see the sub claim
# note above for that.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    data.tls_certificate.github.certificates[length(data.tls_certificate.github.certificates) - 1].sha1_fingerprint
  ]
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
      values   = [for r in local.plan_repos : "${local.org_subject_prefix}/${r}@*:*"]
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
        "${local.org_subject_prefix}/infra-aws@${var.infra_aws_repo_id}:ref:refs/heads/main",
        "${local.org_subject_prefix}/infra-aws@${var.infra_aws_repo_id}:environment:aws-apply",
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

###############################################################################
# Engineer permissions boundary
#
# Consumed by ../identity, which attaches it to the PlatformEngineer permission
# set and requires it on every role an engineer creates. It has to live here
# because a boundary is resolved in the account the session runs in, and
# ../identity runs in management.
#
# A boundary is an INTERSECTION, not a deny list. A policy containing only Deny
# statements grants nothing and would leave every engineer session with zero
# permissions - hence the explicit Allow on everything, narrowed by the denies
# below. Those denies mirror the workloads-OU SCP on purpose: the ceiling a
# person works under and the ceiling a role they create works under should be
# the same ceiling, or the difference becomes an escalation path.
###############################################################################

data "aws_iam_policy_document" "engineer_boundary" {
  statement {
    sid       = "AllowEverythingTheSCPPermits"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "NoLongLivedCredentials"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:PutUserPermissionsBoundary",
      "iam:DeleteUserPermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ProtectAuditAndAccount"
    effect = "Deny"
    actions = [
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
      "iam:DeleteAccountPasswordPolicy",
      "organizations:LeaveOrganization",
      "account:CloseAccount",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ProtectStateAndAuditBuckets"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.org_prefix}-tfstate-*",
      "arn:${data.aws_partition.current.partition}:s3:::${var.org_prefix}-cloudtrail-*",
      "arn:${data.aws_partition.current.partition}:s3:::${var.org_prefix}-s3-access-logs-*",
    ]
  }

  statement {
    sid     = "ProtectPrivilegedRoles"
    effect  = "Deny"
    actions = ["iam:*Role*", "iam:*RolePolicy*", "iam:*PermissionsBoundary*"]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:role/${local.name}-gha-*",
      "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:role/OrganizationAccountAccessRole",
      "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:role/aws-reserved/sso.amazonaws.com/*",
    ]
  }
}

resource "aws_iam_policy" "engineer_boundary" {
  name        = "${var.org_prefix}-engineer-boundary"
  path        = "/"
  description = "Permissions boundary for Identity Center engineers and the roles they create"
  policy      = data.aws_iam_policy_document.engineer_boundary.json
}
