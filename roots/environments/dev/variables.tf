variable "account_id" {
  description = "Workload AWS account this dev root is allowed to deploy to."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the dev VPC (e.g. 10.0.0.0/16)."
  type        = string
}
