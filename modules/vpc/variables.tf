variable "name" {
  description = "Resource name prefix, u25c-<env>-<component> style (e.g. u25c-dev)."
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR for the VPC (e.g. 10.0.0.0/16)."
  type        = string
}

variable "map_public_ip_on_launch" {
  description = "Auto-assign a public IPv4 to instances in the public subnets."
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable the Amazon-provided DNS resolver in the VPC. Required by EKS."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Assign DNS hostnames to instances. Required by EKS."
  type        = bool
  default     = true
}

variable "enable_s3_gateway_endpoint" {
  description = "Create the free S3 gateway endpoint on the public route table."
  type        = bool
  default     = false
}

variable "subnet_tags" {
  description = "Extra tags applied to every public subnet (e.g. kubernetes.io/role/elb)."
  type        = map(string)
  default     = {}
}
