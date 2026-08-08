###############################################################################
# ECR repositories.
#
# One repository per image, created from a map so a caller adds an image by
# adding a key rather than by copying a resource block. Repository names are
# prefixed - "u25c/api" rather than "api" - because the registry is shared by
# the whole account and a bare name collides with the next team's.
#
# There is deliberately no repository policy here. Pulls from inside this
# account already work: the node role carries AmazonEC2ContainerRegistryReadOnly
# (modules/eks/iam.tf). A repository policy is only needed to grant another
# account access, and there is no other account.
###############################################################################

resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name = "${var.name_prefix}/${each.key}"

  # IMMUTABLE means a tag, once pushed, can never point at different bytes.
  # That is what makes promoting an image between environments meaningful -
  # "the tag we tested" and "the tag we deployed" cannot drift apart. The cost
  # is that re-pushing :latest fails, which is the point.
  image_tag_mutability = coalesce(each.value.image_tag_mutability, var.image_tag_mutability)

  # Basic scanning is free and reports CVEs against the OS packages in a layer.
  image_scanning_configuration {
    scan_on_push = coalesce(each.value.scan_on_push, var.scan_on_push)
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
    Name = "${var.name_prefix}/${each.key}"
  })
}

###############################################################################
# Lifecycle policies - the only thing standing between you and an ECR bill that
# grows forever.
#
# Storage is billed per GB per month and nothing expires on its own. A build
# per commit produces an untagged layer set every time the tag moves, and those
# orphans are invisible in the console's default view.
#
# Rules are evaluated in rulePriority order and an image is expired by the first
# rule that selects it, so the untagged rule has to come first - the catch-all
# below would otherwise count orphans towards the keep limit.
###############################################################################

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.repositories

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${coalesce(each.value.untagged_expire_days, var.untagged_expire_days)} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = coalesce(each.value.untagged_expire_days, var.untagged_expire_days)
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the most recent ${coalesce(each.value.max_image_count, var.max_image_count)} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = coalesce(each.value.max_image_count, var.max_image_count)
        }
        action = { type = "expire" }
      },
    ]
  })
}
