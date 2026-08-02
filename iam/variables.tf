variable "account_id" {
  description = "AWS account this configuration is allowed to run against."
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

variable "github_org" {
  description = "GitHub organisation whose workflows may assume these roles."
  type        = string
  default     = "Ubuntu-25c-market-prep"
}

variable "state_bucket" {
  description = "Terraform state bucket created by ../bootstrap."
  type        = string
}

variable "kms_key_arn" {
  description = "Shared KMS key ARN created by ../bootstrap."
  type        = string
}
