variable "cluster_name" {
  description = "Name of the EKS cluster (e.g. u25c-dev)."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes control-plane version. Keep this on a release still in EKS standard support: a version that falls into extended support keeps running, but the control plane costs roughly six times as much per hour and the switch happens automatically. `aws eks describe-cluster-versions` prints the end-of-support date."
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "VPC the cluster runs in. Comes from the vpc module."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the cluster and nodes. Comes from the vpc module's public_subnet_ids."
  type        = list(string)
}

variable "instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "desired_size" {
  description = "Number of nodes the node group aims to run."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of nodes."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes."
  type        = number
  default     = 3
}

variable "permissions_boundary" {
  description = "ARN of a permissions boundary to attach to the IAM roles this module creates. Required when a PlatformEngineer applies (that permission set only allows creating roles that carry the engineer boundary). null when an admin/CI applies."
  type        = string
  default     = null
}

variable "admin_principal_arns" {
  description = "IAM principal ARNs (e.g. the PlatformEngineer/PlatformAdmin SSO roles) granted cluster-admin via EKS access entries. authentication_mode is API, so without an entry here nobody can reach the cluster."
  type        = list(string)
  default     = []
}

variable "authentication_mode" {
  description = "Authentication mode for the EKS cluster access configuration."
  type        = string
  default     = "API"
}
