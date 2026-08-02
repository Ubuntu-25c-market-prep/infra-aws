variable "management_account_id" {
  description = "Management account. IAM Identity Center is administered from here."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "Must be a 12-digit AWS account id."
  }
}

variable "workload_account_id" {
  description = "The single workload account. Where engineers actually build."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.workload_account_id))
    error_message = "Must be a 12-digit AWS account id."
  }
}

variable "region" {
  description = "Region the Identity Center instance lives in. Not the same thing as the home region."
  type        = string
  default     = "us-east-1"
}

variable "org_prefix" {
  description = "Name prefix for groups and permission sets."
  type        = string
  default     = "u25c"
}

variable "access_portal_subdomain" {
  description = <<-EOT
    Custom subdomain for the AWS access portal, without the domain - "ubuntu-25c"
    gives https://ubuntu-25c.awsapps.com/start.

    Set in the Identity Center console, once. There is no API and no Terraform
    resource, and **the choice is irreversible**. This variable exists so the
    portal URL this configuration reports is the one people actually use.

    Empty string falls back to the default identity-store URL.
  EOT
  type        = string
  default     = ""
}

variable "sign_in_name_overrides" {
  description = <<-EOT
    Handle -> sign-in name, for people whose Identity Center account predates the
    convention that the two are the same.

    user_name is immutable in the identity store: changing it destroys the user
    and takes their password and registered MFA device with it. Adopting an
    existing account therefore means keeping its original sign-in name, not
    renaming it to match.
  EOT
  type        = map(string)
  default     = {}
}

variable "email_overrides" {
  description = "Handle -> address, for anyone who should keep a real inbox instead of the generated one."
  type        = map(string)
  default     = {}
}

variable "existing_user_imports" {
  description = <<-EOT
    Users created in the console before this configuration existed, mapped from
    GitHub handle to Identity Center user id. Terraform adopts them instead of
    creating a duplicate person, and normalises their sign-in name to the handle.

      aws identitystore list-users --identity-store-id <d-xxxx> \
        --query 'Users[].{Id:UserId,UserName:UserName}'
  EOT
  type        = map(string)
  default     = {}
}

variable "email_prefix" {
  description = <<-EOT
    Local part of every generated address, up to and including the plus sign.
    Each user gets "<email_prefix><github handle>@<email_domain>".

    Plus-addressing gives 17 unique, deliverable mailboxes without collecting
    anyone's personal email. Password-setup mail lands in the CTO's inbox, which
    is where it is useful - onboarding hands out one-time passwords directly.
  EOT
  type        = string
}

variable "email_domain" {
  description = "Domain part of every generated address."
  type        = string
}

variable "engineer_boundary_policy_name" {
  description = <<-EOT
    Customer-managed policy applied as the permissions boundary on the engineer
    permission set. It must already exist IN THE WORKLOAD ACCOUNT - it is created
    by ../iam. Apply that configuration first or this one fails on assignment.

    Empty string removes the boundary.
  EOT
  type        = string
  default     = "u25c-engineer-boundary"
}

variable "admin_session_duration" {
  description = "ISO-8601 duration for admin and billing sessions. Short on purpose."
  type        = string
  default     = "PT4H"
}

variable "engineer_session_duration" {
  description = "ISO-8601 duration for engineer and read-only sessions. One working day."
  type        = string
  default     = "PT8H"
}
