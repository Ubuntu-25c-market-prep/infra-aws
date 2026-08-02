variable "management_account_id" {
  description = "Organisation management account. Budgets and SCPs are managed from here."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "Must be a 12-digit AWS account id."
  }
}

variable "workload_account_ids" {
  description = <<-EOT
    Member accounts the freeze SCP is attached to when the ceiling trips.
    Do NOT include the management account - SCPs have no effect there.
  EOT
  type        = list(string)
  validation {
    condition     = length(var.workload_account_ids) > 0
    error_message = "At least one workload account is required."
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "org_prefix" {
  type    = string
  default = "u25c"
}

variable "monthly_ceiling_usd" {
  description = "Organisation-wide monthly ceiling. The freeze action fires at a percentage of this."
  type        = string
}

variable "freeze_threshold_percent" {
  description = "Percentage of the ceiling at which the freeze SCP is attached."
  type        = number
  default     = 100
  validation {
    condition     = var.freeze_threshold_percent > 0 && var.freeze_threshold_percent <= 200
    error_message = "Must be between 1 and 200."
  }
}

variable "freeze_approval_model" {
  description = <<-EOT
    AUTOMATIC applies the freeze without asking - use this if an unattended
    overnight runaway is the thing you fear most.
    MANUAL emails you a link to approve - safer against a false positive locking
    out the team mid-sprint.
  EOT
  type        = string
  default     = "AUTOMATIC"
  validation {
    condition     = contains(["AUTOMATIC", "MANUAL"], var.freeze_approval_model)
    error_message = "Must be AUTOMATIC or MANUAL."
  }
}

variable "alert_percentages" {
  description = "Actual-spend percentages that trigger an email."
  type        = list(number)
  default     = [25, 50, 80, 100]
}

variable "per_account_ceilings_usd" {
  description = "Map of account id to its own monthly ceiling."
  type        = map(string)
  default     = {}
}

variable "anomaly_threshold_usd" {
  description = "Minimum absolute impact before a cost anomaly is reported."
  type        = number
  default     = 25
}

variable "alert_emails" {
  description = "Recipients for budget, freeze and anomaly notifications."
  type        = list(string)
  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "At least one recipient is required."
  }
}
