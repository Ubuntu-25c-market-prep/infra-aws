variable "management_account_id" {
  description = "Organisation management account. Runs Organizations, Identity Center, budgets."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "Must be a 12-digit AWS account id."
  }
}

variable "organization_id" {
  description = "Existing organisation to adopt. This configuration never creates one."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "Must be an organisation id of the form o-xxxxxxxxxx."
  }
}

variable "region" {
  description = "Home region. Organizations is global but the provider still needs one."
  type        = string
  default     = "us-east-1"
}

variable "home_region" {
  description = "The only region workload accounts may operate in. Enforced by SCP."
  type        = string
  default     = "us-east-1"
}

variable "org_prefix" {
  description = "Name prefix for every organisation-level resource."
  type        = string
  default     = "u25c"
}

variable "member_accounts" {
  description = <<-EOT
    Existing member accounts to place into OUs, keyed by account id. `name` and
    `email` must match the live account exactly - they are import inputs, not a
    request to change anything. `ou` is one of: workloads, dormant.

    Accounts left out of this map stay where they are. The management account and
    any SUSPENDED account belong here only if you intend Terraform to move them,
    and neither can be moved, so neither should be listed.
  EOT
  type = map(object({
    name  = string
    email = string
    ou    = string
  }))

  validation {
    condition     = alltrue([for a in var.member_accounts : contains(["workloads", "dormant"], a.ou)])
    error_message = "Each account's ou must be either workloads or dormant."
  }
}

variable "cloudtrail_delegated_admin_id" {
  description = <<-EOT
    Account allowed to administer the organisation trail. The trail, its bucket
    and its KMS key already live in the workload account; delegating lets it stay
    there instead of rebuilding the whole audit path in management.

    Empty string disables the delegation.
  EOT
  type        = string
  default     = ""
}

variable "allowed_instance_types" {
  description = <<-EOT
    Instance types the workloads OU may launch. Wildcards allowed.

    This list gates EKS managed node groups and Karpenter as well as direct
    RunInstances calls - autoscaling reaches ec2:RunInstances through a
    service-linked role, and the SCP applies to that role too. Removing a size
    the cluster depends on will look like a Karpenter bug, not a policy change.
  EOT
  type        = list(string)
  default = [
    "t3.*",
    "t3a.*",
    "t4g.*",
    "m5.large",
    "m5.xlarge",
    "m6i.large",
    "m6i.xlarge",
    "m7g.large",
    "m7g.xlarge",
    "c5.large",
    "c5.xlarge",
    "c6i.large",
    "c6i.xlarge",
    "r5.large",
    "r6i.large",
  ]
}

variable "workstream_slugs" {
  description = "Allowed values for the Workstream tag. Mirrors ops-program/program/roster.yaml."
  type        = list(string)
  default = [
    "infra", "security", "scaling", "argocd", "flux", "monitoring", "logging",
    "tracing", "utils", "velero", "rancher", "finops", "istio", "zerotrust", "bedrock",
  ]
}
