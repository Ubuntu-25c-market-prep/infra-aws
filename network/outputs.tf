# Surfaces the module's results so `terraform output` can show them after apply.

output "vpc_id" {
  description = "ID of the platform VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "IPv4 CIDR of the platform VPC."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = module.vpc.public_subnet_ids
}

output "availability_zones" {
  description = "Availability zones the public subnets landed in."
  value       = module.vpc.availability_zones
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = module.vpc.internet_gateway_id
}

output "public_route_table_id" {
  description = "ID of the shared public route table."
  value       = module.vpc.public_route_table_id
}
