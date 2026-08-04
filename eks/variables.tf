variable "account_id" {
  description = "Workload AWS account this layer is allowed to deploy to."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "org_prefix" {
  description = "Short organisation code used in every resource name and in the Org tag. The tag policy in organization/ pins the Org tag to this value, so a literal here would drift the moment the prefix changes."
  type        = string
  default     = "u25c"
}

variable "kubernetes_version" {
  description = "EKS control-plane version."
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS node group."
  type        = list(string)
}

variable "node_desired_size" {
  description = "Number of nodes to run."
  type        = number
}

variable "node_min_size" {
  description = "Minimum number of nodes."
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of nodes."
  type        = number
}

variable "admin_principal_arns" {
  description = "IAM principal ARNs granted cluster-admin (e.g. the PlatformEngineer/PlatformAdmin SSO roles)."
  type        = list(string)
  default     = []
}
