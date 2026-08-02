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
