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

variable "organization_management_account_id" {
  description = <<-EOT
    Management account of the organisation. Required when organization_id is set.

    An organisation trail belongs to the MANAGEMENT account even when a delegated
    administrator creates it, so the trail ARN that CloudTrail presents to this
    bucket and to KMS is in that account, not in this one. Without it here, both
    policies reject the trail and creation fails with
    InsufficientS3BucketPolicyException.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.organization_management_account_id == "" || can(regex("^[0-9]{12}$", var.organization_management_account_id))
    error_message = "Must be empty or a 12-digit AWS account id."
  }
}

variable "organization_member_account_ids" {
  description = <<-EOT
    Every account the organisation trail will capture. Used only to widen the KMS
    encryption context - an organisation trail encrypts on behalf of each member
    account, and an account missing from this list has its events dropped rather
    than rejected, so the trail looks healthy while losing data.

    Ignored when organization_id is empty.
  EOT
  type        = list(string)
  default     = []
}

variable "organization_id" {
  description = <<-EOT
    Organisation to capture with the CloudTrail trail. Setting it converts the
    account trail into an ORGANISATION trail covering every member account.

    Requires this account to be a registered CloudTrail delegated administrator -
    see ../organization. Empty string keeps the trail account-scoped.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.organization_id == "" || can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "Must be empty or an organisation id of the form o-xxxxxxxxxx."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget. Notifications fire at 50%, 80%, 100% actual and 100% forecast."
  type        = string
  default     = "2500"
}

variable "anomaly_threshold_usd" {
  description = "Minimum absolute daily impact before a cost anomaly is reported."
  type        = number
  default     = 50
}

variable "alert_emails" {
  description = "Recipients for budget and cost anomaly alerts."
  type        = list(string)
  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "At least one alert recipient is required - guardrails nobody reads are not guardrails."
  }
}

variable "cloudtrail_retention_days" {
  description = "How long CloudTrail logs are retained in S3."
  type        = number
  default     = 365
}

variable "cloudwatch_retention_days" {
  description = "CloudTrail CloudWatch log group retention."
  type        = number
  default     = 90
}

variable "state_reader_account_ids" {
  description = <<-EOT
    Other accounts allowed to read and write state in this bucket. In practice
    this is the organisation management account, which runs budgets/ but keeps
    its state here so there is one backend rather than two. Empty disables it.
  EOT
  type        = list(string)
  default     = []
}
