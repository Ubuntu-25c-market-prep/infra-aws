###############################################################################
# Cost guardrails with an actual enforcement action.
#
# READ THIS FIRST - AWS has no true hard spending cap.
#
#   * A budget on its own only sends email.
#   * A budget ACTION can attach a restrictive SCP when a threshold trips, which
#     blocks NEW resource creation in the targeted member accounts.
#   * Resources already running keep billing until something terminates them.
#   * SCPs have no effect on the ORGANISATION MANAGEMENT ACCOUNT. Anything built
#     in 909783398044 itself is not protected by the freeze - which is one more
#     reason to build the platform in Dev/Staging/Prod, not in management.
#
# The freeze is therefore a brake, not a kill switch. It stops the bleeding from
# getting worse; it does not undo what is already provisioned.
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
      Workstream = "finops"
      ManagedBy  = "terraform"
      Repo       = "infra-aws"
    }
  }
}

data "aws_partition" "current" {}

locals {
  name = "${var.org_prefix}-org"
}

###############################################################################
# The freeze policy - denies anything that creates ongoing cost
###############################################################################

resource "aws_organizations_policy" "cost_freeze" {
  name        = "${local.name}-cost-freeze"
  description = "Attached automatically by a budget action when spend breaches the ceiling"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyNewSpend"
        Effect = "Deny"
        Action = [
          # Compute
          "ec2:RunInstances",
          "ec2:CreateVolume",
          "ec2:CreateNatGateway",
          "ec2:AllocateAddress",
          "eks:CreateCluster",
          "eks:CreateNodegroup",
          "eks:CreateFargateProfile",
          "ecs:CreateCluster",
          "lambda:CreateFunction",
          # Data
          "rds:CreateDBInstance",
          "rds:CreateDBCluster",
          "elasticache:CreateCacheCluster",
          "es:CreateDomain",
          "opensearch:CreateDomain",
          "dynamodb:CreateTable",
          # Networking and delivery
          "elasticloadbalancing:CreateLoadBalancer",
          "cloudfront:CreateDistribution",
          "globalaccelerator:CreateAccelerator",
          # Managed platform services from the cost model
          "aps:CreateWorkspace",
          "grafana:CreateWorkspace",
          "bedrock:CreateProvisionedModelThroughput",
        ]
        Resource = "*"
      }
    ]
  })
}

###############################################################################
# Role the Budgets service assumes to apply the policy
###############################################################################

data "aws_iam_policy_document" "budget_action_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.management_account_id]
    }
  }
}

data "aws_iam_policy_document" "budget_action" {
  statement {
    effect = "Allow"
    actions = [
      "organizations:AttachPolicy",
      "organizations:DetachPolicy",
      "organizations:ListPoliciesForTarget",
      "organizations:ListTargetsForPolicy",
      "organizations:DescribePolicy",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "budget_action" {
  name               = "${local.name}-budget-action"
  description        = "Assumed by AWS Budgets to attach the cost freeze SCP"
  assume_role_policy = data.aws_iam_policy_document.budget_action_trust.json
}

resource "aws_iam_role_policy" "budget_action" {
  name   = "attach-freeze-scp"
  role   = aws_iam_role.budget_action.id
  policy = data.aws_iam_policy_document.budget_action.json
}

###############################################################################
# Organisation-wide budget with the enforcement action
###############################################################################

resource "aws_budgets_budget" "org_monthly" {
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_ceiling_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = false
    include_refund = false
    include_tax    = true
  }

  # Early and often. With nothing deployed yet, the 25% notice is what tells you
  # something unexpected started running.
  dynamic "notification" {
    for_each = var.alert_percentages
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.alert_emails
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_emails
  }
}

resource "aws_budgets_budget_action" "freeze" {
  budget_name        = aws_budgets_budget.org_monthly.name
  action_type        = "APPLY_SCP_POLICY"
  approval_model     = var.freeze_approval_model
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budget_action.arn

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = var.freeze_threshold_percent
  }

  definition {
    scp_action_definition {
      policy_id  = aws_organizations_policy.cost_freeze.id
      target_ids = var.workload_account_ids
    }
  }

  subscriber {
    subscription_type = "EMAIL"
    address           = var.alert_emails[0]
  }
}

###############################################################################
# Per-account budgets - catch one account running away before the org total does
###############################################################################

resource "aws_budgets_budget" "per_account" {
  for_each = var.per_account_ceilings_usd

  name         = "${local.name}-${each.key}"
  budget_type  = "COST"
  limit_amount = each.value
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "LinkedAccount"
    values = [each.key]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_emails
  }
}

###############################################################################
# Anomaly detection - catches a spike inside a period the budget would miss
###############################################################################

resource "aws_ce_anomaly_monitor" "services" {
  name              = "${local.name}-service-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "immediate" {
  name             = "${local.name}-anomaly"
  frequency        = "IMMEDIATE"
  monitor_arn_list = [aws_ce_anomaly_monitor.services.arn]

  dynamic "subscriber" {
    for_each = var.alert_emails
    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }
}
