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

variable "github_org_id" {
  description = <<-EOT
    Numeric id of the GitHub organisation, from `gh api /orgs/<org> --jq .id`.

    Required because this organisation issues OIDC tokens in the immutable ID
    format - see the note in main.tf. Pinning the id is what stops someone who
    registers the organisation name after a rename from assuming these roles.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_org_id))
    error_message = "Must be the numeric organisation id."
  }
}

variable "infra_aws_repo_id" {
  description = <<-EOT
    Numeric id of this repository, from `gh api /repos/<org>/infra-aws --jq .id`.

    Only the apply role pins a repo id. Its trust uses StringEquals rather than
    StringLike, deliberately - the most privileged role in the account should not
    be reachable through a wildcard.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.infra_aws_repo_id))
    error_message = "Must be the numeric repository id."
  }
}
