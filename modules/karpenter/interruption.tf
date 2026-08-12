###############################################################################
# Interruption handling.
#
# Karpenter watches this SQS queue for events that mean a node is about to go
# away - spot interruptions, rebalance recommendations, scheduled maintenance,
# instance state changes, capacity-reservation reclaims - and drains the node
# gracefully ahead of the two-minute deadline. EventBridge rules forward those
# events into the queue; the controller policy grants receive/delete on it.
###############################################################################

resource "aws_sqs_queue" "interruption" {
  name                      = var.cluster_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = {
    Name = "${var.cluster_name}-karpenter-interruption"
  }
}

# Let EventBridge (and SQS itself) deliver to the queue, and refuse any
# non-TLS access. Mirrors the upstream template's queue policy.
data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid       = "SqsWrite"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }

  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.interruption.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

###############################################################################
# EventBridge rules -> the interruption queue. One per event class Karpenter
# reacts to, matching the upstream CloudFormation template.
###############################################################################

locals {
  interruption_rules = {
    scheduled_change = {
      source      = "aws.health"
      detail_type = "AWS Health Event"
    }
    spot_interruption = {
      source      = "aws.ec2"
      detail_type = "EC2 Spot Instance Interruption Warning"
    }
    rebalance = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance Rebalance Recommendation"
    }
    instance_state_change = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance State-change Notification"
    }
    capacity_reservation = {
      source      = "aws.ec2"
      detail_type = "EC2 Capacity Reservation Instance Interruption Warning"
    }
  }
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_rules

  name = "${var.cluster_name}-karpenter-${each.key}"

  event_pattern = jsonencode({
    source      = [each.value.source]
    detail-type = [each.value.detail_type]
  })

  tags = {
    Name = "${var.cluster_name}-karpenter-${each.key}"
  }
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = local.interruption_rules

  rule      = aws_cloudwatch_event_rule.interruption[each.key].name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.interruption.arn
}
