###############################################################################
# Outputs shared by every file in this module.
###############################################################################

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_arn" {
  description = "ARN of the VPC."
  value       = aws_vpc.main.arn
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

# aws_subnet.public is count-based, so it is a list. [*].id collects the id of
# every subnet into a list, in count order (index 0, 1, ...).
output "public_subnet_ids" {
  description = "IDs of the public subnets, in count order."
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "IPv4 CIDR of each public subnet, in count order."
  value       = aws_subnet.public[*].cidr_block
}

output "availability_zones" {
  description = "Availability zone of each public subnet, in count order."
  value       = aws_subnet.public[*].availability_zone
}

# one() returns the single element of a 0-or-1 list, or null when it is empty -
# safer than [0], which errors when the resource is disabled.
output "internet_gateway_id" {
  description = "ID of the internet gateway, or null when create_internet_gateway is false."
  value       = one(aws_internet_gateway.main[*].id)
}

output "public_route_table_id" {
  description = "ID of the shared public route table."
  value       = aws_route_table.public.id
}

output "s3_gateway_endpoint_id" {
  description = "ID of the S3 gateway endpoint, or null when disabled."
  value       = one(aws_vpc_endpoint.s3[*].id)
}
