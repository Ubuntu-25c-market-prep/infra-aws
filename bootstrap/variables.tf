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
