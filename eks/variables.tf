###############################################################################
# Everything else this layer needs is in ../config.yaml. Only what must not be
# committed lives here, supplied by TF_VAR_* from the gitignored ../.env
# locally, and by the CI workflow on a runner.
###############################################################################

variable "account_id" {
  description = "Workload AWS account this layer is allowed to deploy to. Guards every resource via allowed_account_ids - a wrong-account apply fails immediately instead of half-succeeding."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account id."
  }
}

variable "admin_principal_arns" {
  description = "IAM principal ARNs (the Identity Center permission-set roles) granted cluster-admin via EKS access entries. authentication_mode is API, so an empty list means nobody can reach the cluster. Not looked up with data.aws_iam_roles: that calls iam:ListRoles, which the PlatformEngineer permission set explicitly denies."
  type        = list(string)

  validation {
    condition     = length(var.admin_principal_arns) > 0
    error_message = "At least one admin principal is required, or the cluster is unreachable once created."
  }
}
