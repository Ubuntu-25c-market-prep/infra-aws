###############################################################################
# Velero server role (IRSA) - assumed by the Velero server pod via the
# cluster's OIDC provider. The gitops-flux HelmRelease annotates the shared
# ServiceAccount with this role ARN (eks.amazonaws.com/role-arn), supplied
# out-of-band through a ConfigMap because that repository is public - same
# pattern as the Thanos and KEDA roles.
#
# One role, two AWS services. Velero's AWS plugin (velero-plugin-for-aws)
# handles both halves of a backup with the same credentials: it writes
# resource manifests to S3 (bucket.tf) and it drives native EBS snapshots
# through EC2. A backup that only did one of these would be incomplete - S3
# without the EBS snapshots restores an empty PVC, and EBS snapshots without
# the S3 manifests are data nothing references.
###############################################################################

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "velero_trust" {
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

resource "aws_iam_role" "velero" {
  name                 = "${var.cluster_name}-velero"
  permissions_boundary = var.permissions_boundary
  assume_role_policy   = data.aws_iam_policy_document.velero_trust.json

  tags = {
    Name = "${var.cluster_name}-velero"
  }
}

data "aws_iam_policy_document" "velero" {
  # Object storage half of a backup: resource manifests and backup metadata.
  # Scoped to this one bucket - Velero never needs another.
  statement {
    sid    = "AllowBackupBucketReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.velero.arn}/*"]
  }

  statement {
    sid       = "AllowBackupBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.velero.arn]
  }

  # EBS-snapshot half of a backup, split across three statements by how far
  # each action can actually be scoped down - not all four "*" actions here
  # are equally unavoidable, which is worth reading carefully in review.
  #
  # Describe* calls never support resource-level permissions at all, and
  # CreateSnapshot/CreateVolume have no ARN to scope to until the action that
  # creates them runs. "*" here is the ceiling AWS allows, not a shortcut.
  statement {
    sid    = "AllowEBSSnapshotDiscoveryAndCreation"
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:CreateVolume",
      "ec2:CreateSnapshot",
    ]
    resources = ["*"]
  }

  # CreateTags DOES support resource-level scoping, unlike the four actions
  # above. Restricted to the snapshot/volume resource types, and further
  # gated by ec2:CreateAction so it can only fire in the same API call as a
  # CreateSnapshot or CreateVolume - this role can tag a resource it just
  # created and nothing else. Without that condition this would be a
  # standing "retag anything in EC2" grant, which is exactly the kind of
  # scope creep a resources = ["*"] hides.
  statement {
    sid    = "AllowTaggingOwnSnapshotsAndVolumes"
    effect = "Allow"
    actions = ["ec2:CreateTags"]
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:snapshot/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:volume/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSnapshot", "CreateVolume"]
    }
  }

  # DeleteSnapshot also supports resource-level scoping. Restricted to the
  # snapshot resource type, so this role can never reach a volume or instance
  # through this action.
  #
  # It can still delete ANY snapshot in the account, not only ones this
  # Velero instance created - IAM alone can't tell the difference without a
  # tag condition, and that condition is deliberately not added here. Adding
  # one means keying it to whatever tag velero-plugin-for-aws actually
  # stamps on a snapshot (velero.io/backup-name and similar, from the plugin
  # docs) - worth confirming against a real backup's tags once one exists,
  # not guessed at in a layer that has never run yet.
  statement {
    sid       = "AllowDeletingSnapshots"
    effect    = "Allow"
    actions   = ["ec2:DeleteSnapshot"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:snapshot/*"]
  }
}

resource "aws_iam_role_policy" "velero" {
  name   = "${var.cluster_name}-velero"
  role   = aws_iam_role.velero.id
  policy = data.aws_iam_policy_document.velero.json
}
