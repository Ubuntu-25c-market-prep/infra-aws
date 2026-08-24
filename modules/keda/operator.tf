###############################################################################
# Operator role (IRSA) - assumed by the KEDA operator pod via the cluster's
# OIDC provider. The gitops-flux HelmRelease annotates its ServiceAccount with
# this role ARN (eks.amazonaws.com/role-arn), supplied out-of-band through a
# ConfigMap because that repository is public.
#
# KEDA's AWS triggers are polled by the OPERATOR, not by the scaled workload,
# so this single role is what every aws-* scaler authenticates as. That makes
# it a shared credential across every ScaledObject in the cluster, which is
# why the policy below is read-only and scoped by queue name rather than "*".
###############################################################################

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Trust: only the keda-operator ServiceAccount in the keda namespace.
data "aws_iam_policy_document" "operator_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "operator" {
  name                 = "${var.cluster_name}-keda-operator"
  permissions_boundary = var.permissions_boundary
  assume_role_policy   = data.aws_iam_policy_document.operator_trust.json

  tags = {
    Name = "${var.cluster_name}-keda-operator"
  }
}

data "aws_iam_policy_document" "operator" {
  # Queue-depth triggers. Read-only: KEDA reads ApproximateNumberOfMessages to
  # decide a replica count, and never consumes from the queue - the scaled
  # workload does that with its own credentials.
  #
  # Scoped by name prefix to the three application environments. The one queue
  # that exists today is `u25c-shared`, Karpenter's spot interruption queue,
  # and it is deliberately NOT matched here: nothing in KEDA should be reading
  # the platform's interruption signal.
  statement {
    sid    = "AllowReadApplicationQueueDepth"
    effect = "Allow"
    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [
      for prefix in var.queue_name_prefixes :
      "arn:${data.aws_partition.current.partition}:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${prefix}"
    ]
  }

  # CloudWatch metric triggers. GetMetricData does not support resource-level
  # permissions - there is no metric ARN to scope to - so "*" here is the
  # tightest AWS allows, not a shortcut. It is read-only and returns datapoints
  # only.
  #
  # cloudwatch:ListMetrics is deliberately absent: the aws-cloudwatch scaler is
  # given an explicit namespace, metric name and dimensions, so it never
  # discovers metrics.
  statement {
    sid       = "AllowReadCloudWatchMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:GetMetricData"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "operator" {
  name   = "${var.cluster_name}-keda-operator"
  role   = aws_iam_role.operator.id
  policy = data.aws_iam_policy_document.operator.json
}
