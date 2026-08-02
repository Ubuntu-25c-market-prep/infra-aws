###############################################################################
# Policy documents
#
# SCPs are capped at 5120 characters after whitespace is stripped, which is why
# these are jsonencode'd rather than written as heredocs. `terraform plan` will
# tell you if a statement pushes one over the limit.
###############################################################################

locals {
  # Services with no regional endpoint. Denying them by region would deny IAM,
  # Organizations and STS everywhere, which locks the account out of itself.
  global_services = [
    "iam:*",
    "sts:*",
    "organizations:*",
    "sso:*",
    "sso-directory:*",
    "identitystore:*",
    "account:*",
    "budgets:*",
    "ce:*",
    "cur:*",
    "health:*",
    "support:*",
    "trustedadvisor:*",
    "artifact:*",
    "route53:*",
    "route53domains:*",
    "cloudfront:*",
    "globalaccelerator:*",
    "waf:*",
    "shield:*",
    "servicequotas:*",
    "tag:*",
    "notifications:*",
  ]

  protected_buckets = [
    "arn:aws:s3:::${var.org_prefix}-tfstate-*",
    "arn:aws:s3:::${var.org_prefix}-cloudtrail-*",
    "arn:aws:s3:::${var.org_prefix}-s3-access-logs-*",
  ]
}

###############################################################################
# u25c-org-guardrails -> workloads OU
###############################################################################

resource "aws_organizations_policy" "guardrails" {
  name        = "${local.name}-guardrails"
  description = "Region lock, instance sizing, root user, and audit-trail protection"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # The account root user has no MFA story that scales to 16 people and no
      # audit trail worth the name. Everything goes through Identity Center.
      {
        Sid       = "DenyRootUser"
        Effect    = "Deny"
        Action    = "*"
        Resource  = "*"
        Condition = { StringLike = { "aws:PrincipalArn" = "arn:aws:iam::*:root" } }
      },

      # One region. A cluster accidentally built in eu-west-1 is invisible to
      # every dashboard, runbook and budget filter this programme has.
      {
        Sid       = "DenyNonHomeRegion"
        Effect    = "Deny"
        NotAction = local.global_services
        Resource  = "*"
        Condition = { StringNotEquals = { "aws:RequestedRegion" = [var.home_region] } }
      },

      # Scoped to the instance ARN so it constrains the size being launched
      # rather than the whole RunInstances call.
      {
        Sid       = "DenyLargeInstances"
        Effect    = "Deny"
        Action    = "ec2:RunInstances"
        Resource  = "arn:aws:ec2:*:*:instance/*"
        Condition = { StringNotLike = { "ec2:InstanceType" = var.allowed_instance_types } }
      },

      # cloudtrail:UpdateTrail is deliberately absent - bootstrap/ still has to
      # be able to convert the trail to an organisation trail. Deleting it and
      # silencing it are the actions that actually destroy evidence.
      {
        Sid    = "ProtectAudit"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "kms:ScheduleKeyDeletion",
          "kms:DisableKey",
          "iam:DeleteAccountPasswordPolicy",
          "organizations:LeaveOrganization",
          "account:CloseAccount",
        ]
        Resource = "*"
      },

      {
        Sid      = "ProtectStateBuckets"
        Effect   = "Deny"
        Action   = ["s3:DeleteBucket", "s3:DeleteBucketPolicy", "s3:PutBucketPublicAccessBlock"]
        Resource = local.protected_buckets
      },

      # Everything in this programme authenticates through OIDC or Identity
      # Center. A long-lived access key is the one credential that can leak into
      # a public repository and stay valid.
      {
        Sid      = "NoLongLivedCredentials"
        Effect   = "Deny"
        Action   = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile"]
        Resource = "*"
      },
    ]
  })
}

###############################################################################
# u25c-org-dormant-freeze -> dormant OU
#
# Staging and Prod exist because closing an AWS account is irreversible and
# ADR 0003 wanted the decision reversible. They are not used. This makes that
# true rather than merely intended: read-only, no spend, no surprises.
#
# Lifting it is one detach from the management account.
###############################################################################

resource "aws_organizations_policy" "dormant_freeze" {
  name        = "${local.name}-dormant-freeze"
  description = "Dormant accounts may be inspected and nothing else"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyEverythingButInspection"
        Effect = "Deny"
        NotAction = [
          "organizations:Describe*",
          "organizations:List*",
          "iam:Get*",
          "iam:List*",
          "sts:GetCallerIdentity",
          "cloudtrail:LookupEvents",
          "ce:*",
          "budgets:Describe*",
          "health:*",
          "support:*",
          "account:Get*",
        ]
        Resource = "*"
      },
    ]
  })
}

###############################################################################
# u25c-org-tagging -> workloads OU
#
# Report-only on purpose: no `enforced_for`. An enforcing tag policy rejects
# resource creation outright, which turns one missing tag into a failed apply
# halfway through a wave. Compliance shows up in Resource Groups first; turn on
# enforcement once FinOps showback says it is already clean.
###############################################################################

resource "aws_organizations_policy" "tagging" {
  name        = "${local.name}-tagging"
  description = "Reports non-compliant tags. Does not block resource creation."
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = {
      Org = {
        tag_key   = { "@@assign" = "Org" }
        tag_value = { "@@assign" = [var.org_prefix] }
      }
      Env = {
        tag_key   = { "@@assign" = "Env" }
        tag_value = { "@@assign" = ["dev", "stage", "prod", "shared"] }
      }
      Workstream = {
        tag_key   = { "@@assign" = "Workstream" }
        tag_value = { "@@assign" = var.workstream_slugs }
      }
      ManagedBy = {
        tag_key   = { "@@assign" = "ManagedBy" }
        tag_value = { "@@assign" = ["terraform", "flux", "argocd", "console"] }
      }
      Repo = {
        tag_key = { "@@assign" = "Repo" }
      }
    }
  })
}
