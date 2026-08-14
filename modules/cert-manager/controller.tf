###############################################################################
# Controller role (IRSA) - assumed by the cert-manager controller pod via the
# cluster's OIDC provider. The gitops-flux HelmRelease annotates its
# ServiceAccount with this role ARN (eks.amazonaws.com/role-arn), supplied
# out-of-band through a ConfigMap because that repository is public.
#
# The permission policy is the upstream cert-manager Route 53 policy, tightened:
# the write statement is additionally conditioned on record name and type, so
# this role can only ever touch _acme-challenge TXT records - it cannot repoint
# a live hostname.
###############################################################################

data "aws_partition" "current" {}

# Trust: only the cert-manager ServiceAccount in the cert-manager namespace.
data "aws_iam_policy_document" "controller_trust" {
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

resource "aws_iam_role" "controller" {
  name                 = "${var.cluster_name}-cert-manager-controller"
  permissions_boundary = var.permissions_boundary
  assume_role_policy   = data.aws_iam_policy_document.controller_trust.json

  tags = {
    Name = "${var.cluster_name}-cert-manager-controller"
  }
}

data "aws_iam_policy_document" "controller" {
  # ACME polls the change until it reports INSYNC. Change ids are opaque and
  # cannot be scoped to a zone, so this statement stays broad - as upstream.
  statement {
    sid       = "AllowGetChange"
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::change/*"]
  }

  # Write the challenge record. Scoped to one zone, and further to TXT records
  # named _acme-challenge.*. Upstream stops at the zone; this goes further.
  statement {
    sid       = "AllowChallengeRecordWrites"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/${var.hosted_zone_id}"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }

    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = ["_acme-challenge.*"]
    }
  }

  # Read records to decide whether the challenge record already exists.
  statement {
    sid       = "AllowListRecords"
    effect    = "Allow"
    actions   = ["route53:ListResourceRecordSets"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/${var.hosted_zone_id}"]
  }

  # Resolve a domain name to its zone id. The action takes no resource, so it
  # cannot be scoped. Returns zone names and ids only, no record data.
  statement {
    sid       = "AllowZoneLookup"
    effect    = "Allow"
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "controller" {
  name   = "${var.cluster_name}-cert-manager-controller"
  role   = aws_iam_role.controller.id
  policy = data.aws_iam_policy_document.controller.json
}