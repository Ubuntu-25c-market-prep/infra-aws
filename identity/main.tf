###############################################################################
# IAM Identity Center: who signs in, and as what.
#
# The model, in one paragraph. Everybody signs in at one portal URL with their
# GitHub handle. Group membership decides which roles appear once they are in.
# There are four roles, not fifteen: a permission set says what a person may
# attempt, the SCP on the workloads OU says what the account will allow, and the
# permissions boundary says what a role they create may inherit. Least privilege
# comes from those three together, not from writing fifteen bespoke policies that
# each block somebody halfway through a task.
#
# Nothing here costs money. Identity Center is free.
#
# ORDER MATTERS: ../iam must be applied first. The engineer permission set
# attaches a permissions boundary that has to already exist in the workload
# account.
###############################################################################

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.management_account_id]

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

# The instance is created by enabling Identity Center in the console, once, and
# cannot be created by Terraform at all.
data "aws_ssoadmin_instances" "this" {}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  managed_policy = "arn:${data.aws_partition.current.partition}:iam::aws:policy"

  # Created by ../iam, in the workload account.
  engineer_boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${var.workload_account_id}:policy/${var.engineer_boundary_policy_name}"

  # Which permission set each access group gets, and where.
  assignments = {
    admin_workload    = { group = "cto", permission_set = "admin", account = var.workload_account_id }
    admin_management  = { group = "cto", permission_set = "admin", account = var.management_account_id }
    engineer          = { group = "engineers", permission_set = "engineer", account = var.workload_account_id }
    readonly_workload = { group = "all", permission_set = "readonly", account = var.workload_account_id }
    # Everyone can read the management account so the budget that governs the
    # programme is visible to the people it constrains.
    readonly_management = { group = "all", permission_set = "readonly", account = var.management_account_id }
    billing             = { group = "billing", permission_set = "billing", account = var.management_account_id }
  }
}

###############################################################################
# Groups
###############################################################################

# Access groups. These carry permission sets.
resource "aws_identitystore_group" "access" {
  for_each = local.access_group_members

  identity_store_id = local.identity_store_id
  display_name      = "${var.org_prefix}-${each.key}"
  description       = "Access group: ${each.key}"
}

# Workstream groups. These carry NOTHING today, deliberately.
#
# They mirror the fifteen GitHub teams so that the day a workstream needs its own
# scoped permission set - a Bedrock model-access policy, say - it is a data
# change here rather than a redesign. They also make "who owns this" answerable
# from the AWS console without opening GitHub.
resource "aws_identitystore_group" "workstream" {
  for_each = toset(local.workstreams)

  identity_store_id = local.identity_store_id
  display_name      = "${var.org_prefix}-ws-${each.key}"
  description       = "Workstream ${each.key}. No permission set attached - see main.tf."
}

###############################################################################
# Users
#
# No password is set here, and none can be. AWS exposes no API for issuing a
# one-time password; that is a console action, per user, described in
# ops-program/runbooks/onboard-to-aws.md. Terraform's job ends at "the account
# exists and is in the right groups".
###############################################################################

import {
  for_each = var.existing_user_imports

  to = aws_identitystore_user.this[each.key]
  id = "${local.identity_store_id}/${each.value}"
}

resource "aws_identitystore_user" "this" {
  for_each = local.people

  identity_store_id = local.identity_store_id

  # The GitHub handle. One identifier across GitHub, the board and AWS - except
  # for accounts that predate the convention, which keep their original name
  # because renaming destroys the user.
  user_name    = lookup(var.sign_in_name_overrides, each.key, each.key)
  display_name = "${each.value.first} (${each.key})"

  # The directory requires both halves of a name and the roster only carries
  # first names. Putting the handle in family_name keeps the GitHub mapping
  # visible in the console; people can correct their own profile afterwards.
  name {
    given_name  = each.value.first
    family_name = each.key
  }

  emails {
    value   = lookup(var.email_overrides, each.key, "${var.email_prefix}${each.key}@${var.email_domain}")
    primary = true
  }
}

resource "aws_identitystore_group_membership" "access" {
  for_each = local.access_memberships

  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.access[each.value.group].group_id
  member_id         = aws_identitystore_user.this[each.value.handle].user_id
}

resource "aws_identitystore_group_membership" "workstream" {
  for_each = local.workstream_memberships

  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.workstream[each.value.workstream].group_id
  member_id         = aws_identitystore_user.this[each.value.handle].user_id
}

###############################################################################
# Permission sets
###############################################################################

# CTO. Unrestricted inside the workload account, and the only role that can
# administer the organisation itself.
resource "aws_ssoadmin_permission_set" "admin" {
  name             = "${var.org_prefix}-PlatformAdmin"
  description      = "Full administrative access. CTO only."
  instance_arn     = local.instance_arn
  session_duration = var.admin_session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  managed_policy_arn = "${local.managed_policy}/AdministratorAccess"
}

# Everyone building the platform. PowerUserAccess covers every service but stops
# at IAM, and half of this programme is IRSA, Pod Identity and OIDC trust - so
# IAM role and policy management is added back, under a boundary.
resource "aws_ssoadmin_permission_set" "engineer" {
  name             = "${var.org_prefix}-PlatformEngineer"
  description      = "PowerUser plus scoped IAM, bounded. The working role."
  instance_arn     = local.instance_arn
  session_duration = var.engineer_session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "engineer_poweruser" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.engineer.arn
  managed_policy_arn = "${local.managed_policy}/PowerUserAccess"
}

# PowerUserAccess grants iam:ListRoles and nothing else under iam:. Terraform reads
# every resource back the moment it creates it, so a role that can CreateRole but not
# GetRole fails every apply half-way through - leaving an orphaned role in the account
# and nothing in state, which is worse than failing at the start. Reads carry no
# escalation risk on their own, and the ProtectPrivilegedRoles deny below still decides
# WHICH roles are readable.
#
# Managed rather than an explicit action list on purpose. The set of reads the AWS
# provider issues grows with every resource type a new layer introduces, and each
# omission is discovered the same way this one was: as a half-finished apply.
resource "aws_ssoadmin_managed_policy_attachment" "engineer_iam_read" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.engineer.arn
  managed_policy_arn = "${local.managed_policy}/IAMReadOnlyAccess"
}

data "aws_iam_policy_document" "engineer_iam" {
  # Creating a role, and attaching anything to it, only works if the new role
  # carries the same boundary this session runs under. Without this condition an
  # engineer can create an administrator role and assume it - the boundary caps
  # their session, not the sessions of roles they invent.
  statement {
    sid    = "ManageBoundedRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.engineer_boundary_arn]
    }
  }

  # Operations that carry no escalation risk on their own, and that the
  # iam:PermissionsBoundary condition key does not support.
  statement {
    sid    = "ManageRoleMetadata"
    effect = "Allow"
    actions = [
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      # Every layer sets default_tags, so the first tag value that changes issues an
      # untag call. Granting Tag without Untag is the same half-finished apply in a
      # different costume.
      "iam:UntagOpenIDConnectProvider",
      "iam:PassRole",
    ]
    resources = ["*"]
  }

  # Taking the boundary off a role puts it back on the escalation path.
  statement {
    sid       = "KeepTheBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  # The roles that hold the keys to the account. An engineer who can rewrite the
  # CI apply role's trust policy is an administrator with extra steps.
  statement {
    sid    = "ProtectPrivilegedRoles"
    effect = "Deny"
    actions = [
      "iam:*Role*",
      "iam:*RolePolicy*",
      "iam:*PermissionsBoundary*",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${var.workload_account_id}:role/${var.org_prefix}-shared-gha-*",
      "arn:${data.aws_partition.current.partition}:iam::${var.workload_account_id}:role/OrganizationAccountAccessRole",
      "arn:${data.aws_partition.current.partition}:iam::${var.workload_account_id}:role/aws-reserved/sso.amazonaws.com/*",
    ]
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "engineer" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.engineer.arn
  inline_policy      = data.aws_iam_policy_document.engineer_iam.json
}

# PowerUser plus iam:CreateRole is a path to administrator in two calls. The
# boundary closes it: every session runs inside the boundary's ceiling, and the
# same policy is what engineers must attach to roles they create.
#
# The policy is created by ../iam, in the workload account. Referenced by name
# because a permission set is provisioned into each account separately.
resource "aws_ssoadmin_permissions_boundary_attachment" "engineer" {
  count = var.engineer_boundary_policy_name == "" ? 0 : 1

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.engineer.arn

  permissions_boundary {
    customer_managed_policy_reference {
      name = var.engineer_boundary_policy_name
      path = "/"
    }
  }
}

# The fallback. Also the right role for looking at something you are not on the
# hook for, which is most of what sixteen people do in a shared account.
resource "aws_ssoadmin_permission_set" "readonly" {
  name             = "${var.org_prefix}-ReadOnly"
  description      = "Read-only across every service. Everyone gets this."
  instance_arn     = local.instance_arn
  session_duration = var.engineer_session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "readonly" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.readonly.arn
  managed_policy_arn = "${local.managed_policy}/ReadOnlyAccess"
}

# The finops workstream owns budgets and cost anomaly detection, which live in
# the management account and are invisible to ReadOnlyAccess.
resource "aws_ssoadmin_permission_set" "billing" {
  name             = "${var.org_prefix}-Billing"
  description      = "Budgets, Cost Explorer and billing. The finops workstream."
  instance_arn     = local.instance_arn
  session_duration = var.admin_session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "billing" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.billing.arn
  managed_policy_arn = "${local.managed_policy}/job-function/Billing"
}

resource "aws_ssoadmin_managed_policy_attachment" "billing_readonly" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.billing.arn
  managed_policy_arn = "${local.managed_policy}/AWSBillingReadOnlyAccess"
}

###############################################################################
# Assignments
#
# Groups, never individual users. A person joining a workstream is a membership
# change; it should never require touching an account assignment.
###############################################################################

locals {
  permission_set_arns = {
    admin    = aws_ssoadmin_permission_set.admin.arn
    engineer = aws_ssoadmin_permission_set.engineer.arn
    readonly = aws_ssoadmin_permission_set.readonly.arn
    billing  = aws_ssoadmin_permission_set.billing.arn
  }
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.assignments

  instance_arn       = local.instance_arn
  permission_set_arn = local.permission_set_arns[each.value.permission_set]

  principal_type = "GROUP"
  principal_id   = aws_identitystore_group.access[each.value.group].group_id

  target_type = "AWS_ACCOUNT"
  target_id   = each.value.account
}
