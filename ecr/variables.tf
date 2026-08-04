variable "account_id" {
  description = "Workload AWS account this layer is allowed to deploy to."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "org_prefix" {
  description = "Short organisation code. Doubles as the registry namespace, so repositories are named <org_prefix>/<image>."
  type        = string
  default     = "u25c"
}

variable "repositories" {
  description = "Repositories to create, keyed by short image name. See modules/ecr for the per-repository overrides."
  type = map(object({
    image_tag_mutability = optional(string)
    scan_on_push         = optional(bool)
    untagged_expire_days = optional(number)
    max_image_count      = optional(number)
  }))
  default = {}
}

variable "untagged_expire_days" {
  description = "Delete untagged images this many days after they were pushed."
  type        = number
  default     = 14
}

variable "max_image_count" {
  description = "Keep at most this many images per repository."
  type        = number
  default     = 30
}
