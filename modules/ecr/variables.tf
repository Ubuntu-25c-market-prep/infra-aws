variable "name_prefix" {
  description = "Registry namespace every repository sits under (e.g. u25c, giving u25c/api)."
  type        = string
}

variable "repositories" {
  description = <<-EOT
    Repositories to create, keyed by short image name. Every field is optional -
    a repository with no overrides takes the module defaults below:

      repositories = {
        api = {}
        web = { image_tag_mutability = "MUTABLE" }
      }
  EOT

  type = map(object({
    image_tag_mutability = optional(string)
    scan_on_push         = optional(bool)
    untagged_expire_days = optional(number)
    max_image_count      = optional(number)
  }))

  default = {}
}

variable "image_tag_mutability" {
  description = "Default tag mutability. IMMUTABLE stops a pushed tag from ever pointing at different bytes, which is what makes promoting one image across environments meaningful."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "scan_on_push" {
  description = "Run basic vulnerability scanning when an image is pushed. Free."
  type        = bool
  default     = true
}

variable "untagged_expire_days" {
  description = "Delete untagged images this many days after they were pushed. Untagged layers are the orphans left behind every time a tag moves."
  type        = number
  default     = 14
}

variable "max_image_count" {
  description = "Keep at most this many images per repository. Storage is billed per GB per month and nothing expires on its own."
  type        = number
  default     = 30
}

variable "encryption_type" {
  description = "AES256 (free, AWS-managed) or KMS (customer-managed key, billed per request)."
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}

variable "kms_key_arn" {
  description = "Customer-managed key for image layers. Required when encryption_type is KMS, ignored otherwise."
  type        = string
  default     = null
}

variable "force_delete" {
  description = "Allow terraform destroy to delete a repository that still holds images. False makes the destroy fail instead, which is the safer default."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags merged into every repository. Name is set by the module."
  type        = map(string)
  default     = {}
}
