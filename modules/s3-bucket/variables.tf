variable "name" {
  description = <<-EOT
    Bucket name. S3 names are globally unique across every AWS account, not just
    this one, so a generic name can fail at create time with BucketAlreadyExists
    against a bucket you cannot see. Suffix the account id unless the name is
    already distinctive.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be 3-63 characters of lowercase letters, digits, dots or hyphens, starting and ending alphanumeric."
  }
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for server-side encryption. The shared platform key comes from bootstrap's kms_key_arn output."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

variable "log_bucket" {
  description = "Bucket receiving S3 server access logs. Empty string disables access logging entirely."
  type        = string
  default     = ""
}

variable "log_prefix" {
  description = "Key prefix for delivered access logs. Ignored when log_bucket is empty."
  type        = string
  default     = ""
}

variable "noncurrent_expiration_days" {
  description = "Days after which a noncurrent object version is deleted. Versioning is always on, so without this every overwrite bills forever."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_expiration_days > 0
    error_message = "noncurrent_expiration_days must be greater than zero."
  }
}

variable "expiration_days" {
  description = "Days after which a current object version expires. null keeps current objects indefinitely, which is the right default for data you did not generate."
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days == null || try(var.expiration_days > 0, false)
    error_message = "expiration_days must be null or greater than zero."
  }
}

variable "abort_incomplete_multipart_days" {
  description = "Days after which an incomplete multipart upload is aborted. Orphaned parts are billed as storage and are invisible in the console object listing."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_days > 0
    error_message = "abort_incomplete_multipart_days must be greater than zero."
  }
}

variable "force_destroy" {
  description = "Allow Terraform to delete a bucket that still holds objects. Leave false for anything carrying real data - the guardrail is worth more than the convenience."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged onto the bucket. The provider's default_tags already carry org, env, workstream and ownership."
  type        = map(string)
  default     = {}
}
