###############################################################################
# ECR repositories - one per image, built from a list of names so that adding
# an image means adding a name, not copying a resource block.
#
# Repository names are prefixed ("25c-project/api", not "api") because the
# registry is shared by the whole account and a bare name collides with the
# next team's.
#
# There is deliberately no repository policy here. Pulls from inside this
# account already work: the node role carries AmazonEC2ContainerRegistryReadOnly
# (modules/eks/iam.tf). A repository policy is only needed to grant ANOTHER
# account access, and there is no other account.
###############################################################################

resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name = "${var.name_prefix}/${each.value}"

  # IMMUTABLE means a tag, once pushed, can never point at different bytes. That
  # is what makes promoting an image between environments meaningful - "the tag
  # we tested" and "the tag we deployed" cannot drift apart. The cost is that
  # re-pushing :latest fails, which is the point.
  image_tag_mutability = var.image_tag_mutability

  # Basic scanning is free and reports CVEs against the OS packages in a layer.
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # AES256 is free and managed by AWS. KMS costs per request and is only worth
  # it when an audit requires a customer-managed key for image layers.
  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  # False means `terraform destroy` refuses while images exist, which is the
  # behaviour you want the day someone destroys the wrong layer.
  force_delete = var.force_delete

  tags = merge(var.tags, {
    Name = "${var.name_prefix}/${each.value}"
  })
}

###############################################################################
# Lifecycle policy - deletes untagged images, and nothing else.
#
# Storage is billed per GB per month and ECR expires nothing on its own, so
# something has to clean up. Untagged images are the safe thing to delete: no
# tag means no deployment can be referring to them.
#
# There is deliberately NO "keep only the newest N images" rule. That kind of
# rule counts tagged images too, so a release still running in production gets
# expired once enough newer builds pile up behind it, and the next pod restart
# fails to pull. Delete by "is it referenced", not by "is it old".
###############################################################################

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.repositories

  repository = aws_ecr_repository.this[each.value].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expire_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expire_days
        }
        action = { type = "expire" }
      },
    ]
  })
}
