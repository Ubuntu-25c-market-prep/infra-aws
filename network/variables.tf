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
  description = "Short organisation code used in every resource name, in the SSM parameter paths downstream layers read, and in the Org tag. The tag policy in organization/ pins the Org tag to this value, so a literal here would drift the moment the prefix changes."
  type        = string
  default     = "u25c"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the platform VPC (e.g. 10.0.0.0/16)."
  type        = string
}

variable "az_count" {
  description = "How many availability zones to spread public subnets across. Two is the EKS minimum (ADR 0006)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "EKS requires subnets in at least two availability zones."
  }
}
