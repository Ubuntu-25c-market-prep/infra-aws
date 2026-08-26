###############################################################################
# Controller role (IRSA) - assumed by the external-dns controller pod via the
# cluster's OIDC provider. The gitops-flux HelmRelease annotates its
# ServiceAccount with this role ARN (eks.amazonaws.com/role-arn), supplied
# out-of-band through a ConfigMap because that repository is public.
#
# The permission policy is the upstream external-dns Route 53 policy, tightened
# twice: writes are scoped to one hosted zone rather than hostedzone/*, and
# further to the record types external-dns actually publishes - so this role
# cannot rewrite the zone's NS delegation or its CAA records.
###############################################################################

data "aws_partition" "current" {}

# Trust: only the external-dns ServiceAccount in the external-dns namespace.
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
  name                 = "${var.cluster_name}-external-dns-controller"
  permissions_boundary = var.permissions_boundary
  assume_role_policy   = data.aws_iam_policy_document.controller_trust.json

  tags = {
    Name = "${var.cluster_name}-external-dns-controller"
  }
}

data "aws_iam_policy_document" "controller" {
  # Publish and retract records. Scoped to one zone, and further to the types
  # external-dns manages - upstream stops at hostedzone/* with no type
  # condition. Excluding NS and SOA keeps the delegation intact; excluding CAA
  # means this role cannot authorise a different certificate authority for the
  # domain cert-manager is about to issue from.
  statement {
    sid       = "AllowManagedRecordWrites"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/${var.hosted_zone_id}"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = var.managed_record_types
    }
  }

  # Read the zone to reconcile desired state against what is already published,
  # and to read back its own TXT registry records on startup.
  statement {
    sid       = "AllowListRecords"
    effect    = "Allow"
    actions   = ["route53:ListResourceRecordSets"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/${var.hosted_zone_id}"]
  }

  # external-dns builds a zone cache at startup and filters client-side, so it
  # calls ListHostedZones even when a single zone is pinned. Neither action
  # takes a resource, so neither can be scoped. Both return zone names and ids
  # only, no record data.
  #
  # route53:ListTagsForResource is deliberately absent. Upstream includes it,
  # but it is only called when zones are selected by tag; this layer pins the
  # zone id instead. Add it here if --aws-zone-tags is ever introduced.
  statement {
    sid    = "AllowZoneDiscovery"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "controller" {
  name   = "${var.cluster_name}-external-dns-controller"
  role   = aws_iam_role.controller.id
  policy = data.aws_iam_policy_document.controller.json
}
