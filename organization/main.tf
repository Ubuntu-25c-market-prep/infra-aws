###############################################################################
# Organisation structure: OUs, account placement, guardrail policies.
#
# READ THIS FIRST - this configuration can lock people out.
#
#   * SCPs are a ceiling, not a grant. They cannot give anyone access; they can
#     only take it away, and they take it away from EVERY principal in the target
#     - including the account root user and the CTO.
#   * SCPs have no effect on the MANAGEMENT ACCOUNT. That is not a gap, it is the
#     escape hatch: whatever these policies break in a member account, an admin in
#     the management account can still detach them.
#   * The default FullAWSAccess policy stays attached everywhere. These policies
#     are deny-only overlays on top of it. Detaching FullAWSAccess denies
#     everything, immediately, to everyone.
#
# Nothing here costs money.
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

locals {
  name = "${var.org_prefix}-org"

  ou_ids = {
    workloads = aws_organizations_organizational_unit.workloads.id
    dormant   = aws_organizations_organizational_unit.dormant.id
  }
}

###############################################################################
# The organisation itself - imported, never created
#
# The org predates this configuration. Terraform adopts it to manage two things
# it is otherwise impossible to express in code: which policy types are enabled,
# and which AWS services may act organisation-wide.
###############################################################################

import {
  to = aws_organizations_organization.this
  id = var.organization_id
}

resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]

  aws_service_access_principals = [
    "sso.amazonaws.com",
    "cloudtrail.amazonaws.com",
  ]

  # Removing this resource from state is recoverable. Letting Terraform destroy
  # the organisation is not - it would eject every member account.
  lifecycle {
    prevent_destroy = true
  }
}

###############################################################################
# Organisational units
#
# Two, because there are only two things an account can be here: the one place
# work happens, or a placeholder that must not cost anything. A deeper hierarchy
# would be aspirational rather than descriptive.
#
# The management account stays at the root. So does any SUSPENDED account - AWS
# will not move an account that is pending closure.
###############################################################################

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "${var.org_prefix}-workloads"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "dormant" {
  name      = "${var.org_prefix}-dormant"
  parent_id = aws_organizations_organization.this.roots[0].id
}

###############################################################################
# Account placement
#
# `parent_id` is the only attribute this configuration is really setting. Name
# and email are import inputs; changing either through Terraform triggers an AWS
# account-modification flow nobody wants to discover during a plan.
###############################################################################

import {
  for_each = var.member_accounts

  to = aws_organizations_account.member[each.key]
  id = each.key
}

resource "aws_organizations_account" "member" {
  for_each = var.member_accounts

  name      = each.value.name
  email     = each.value.email
  parent_id = local.ou_ids[each.value.ou]

  # A `terraform destroy` must never be able to close a real AWS account.
  close_on_deletion = false

  lifecycle {
    ignore_changes = [name, email, role_name, iam_user_access_to_billing, tags, tags_all]
  }
}

###############################################################################
# Guardrail attachments
#
# Attached to OUs rather than to the root. The root would also cover the
# management account, and denying the management account its own escape hatch is
# how a one-line policy mistake becomes a support ticket.
###############################################################################

resource "aws_organizations_policy_attachment" "guardrails" {
  policy_id = aws_organizations_policy.guardrails.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "dormant_freeze" {
  policy_id = aws_organizations_policy.dormant_freeze.id
  target_id = aws_organizations_organizational_unit.dormant.id
}

resource "aws_organizations_policy_attachment" "tagging" {
  policy_id = aws_organizations_policy.tagging.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

###############################################################################
# CloudTrail delegated administration
#
# The organisation trail has to be created by the management account or by a
# delegated administrator. Delegating to the workload account keeps the trail,
# its S3 bucket and its KMS key where bootstrap/ already built them.
#
# ONE THING THE DELEGATION DOES NOT BUY. A delegated administrator can create,
# update and delete organisation trails, but it CANNOT convert an existing
# account-level trail into an organisation trail - that is management-account
# only. Setting is_organization_trail on the trail bootstrap/ already made
# therefore fails with NotOrganizationMasterAccountException; the trail has to be
# replaced, not updated. See the AWS delegated-administrator documentation,
# footnote 2 on the capability table.
###############################################################################

resource "aws_organizations_delegated_administrator" "cloudtrail" {
  count = var.cloudtrail_delegated_admin_id == "" ? 0 : 1

  account_id        = var.cloudtrail_delegated_admin_id
  service_principal = "cloudtrail.amazonaws.com"

  depends_on = [aws_organizations_organization.this]
}
