###############################################################################
# Inputs shared by every file in this module. Nothing below is required except
# the name and the CIDR - the defaults describe the common case, and a caller
# overrides any of them without editing the module.
###############################################################################

variable "name" {
  description = "Resource name prefix, u25c-<env>-<component> style (e.g. u25c-shared)."
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR for the VPC (e.g. 10.0.0.0/16)."
  type        = string
}

###############################################################################
# VPC (vpc.tf)
###############################################################################

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

variable "instance_tenancy" {
  description = "Tenancy of instances launched into the VPC: default, dedicated or host."
  type        = string
  default     = "default"
}

###############################################################################
# Internet gateway (igw.tf)
###############################################################################

variable "create_internet_gateway" {
  description = "Create an internet gateway and the 0.0.0.0/0 route that uses it. False gives a VPC with no route to the internet."
  type        = bool
  default     = true
}

###############################################################################
# Subnets (subnets.tf)
###############################################################################

variable "az_count" {
  description = "How many public subnets to create, one per availability zone. Zones are taken from the provider's region, so the module is not tied to one region."
  type        = number
  default     = 2
}

variable "map_public_ip_on_launch" {
  description = "Auto-assign a public IPv4 to instances in the public subnets. This is what makes them public - false means no egress without NAT."
  type        = bool
  default     = true
}

variable "subnet_tags" {
  description = "Extra tags applied to every public subnet (e.g. kubernetes.io/role/elb)."
  type        = map(string)
  default     = {}
}

###############################################################################
# Routing (route-table.tf)
###############################################################################

variable "extra_routes" {
  description = <<-EOT
    Additional routes on the public route table, keyed by a stable name (the key
    only names the route in state). Set exactly one target per route -
    nat_gateway_id, transit_gateway_id, and so on. The 0.0.0.0/0 route to the
    internet gateway is created by create_internet_gateway, not here.
  EOT

  type = map(object({
    destination_cidr_block      = optional(string)
    destination_ipv6_cidr_block = optional(string)
    gateway_id                  = optional(string)
    nat_gateway_id              = optional(string)
    transit_gateway_id          = optional(string)
    vpc_peering_connection_id   = optional(string)
    network_interface_id        = optional(string)
  }))

  default = {}
}

###############################################################################
# Endpoints (endpoints.tf)
###############################################################################

variable "enable_s3_gateway_endpoint" {
  description = "Create the free S3 gateway endpoint on the public route table."
  type        = bool
  default     = false
}
