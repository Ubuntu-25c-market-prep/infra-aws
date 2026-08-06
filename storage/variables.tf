variable "account_id" {
  description = "AWS account this configuration is allowed to run against. The workload account."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account id."
  }
}

variable "region" {
  description = "Primary region for the platform."
  type        = string
  default     = "us-east-1"
}

variable "org_prefix" {
  description = "Short organisation code used in every resource name."
  type        = string
  default     = "u25c"
}

variable "kms_key_arn" {
  description = "Shared KMS key ARN created by ../bootstrap. From `terraform -chdir=../bootstrap output -raw kms_key_arn`."
  type        = string
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}
