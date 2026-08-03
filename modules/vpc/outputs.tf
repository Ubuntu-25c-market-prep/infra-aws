output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
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

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = aws_internet_gateway.main.id
}

output "public_route_table_id" {
  description = "ID of the shared public route table."
  value       = aws_route_table.public.id
}

# The endpoint is count 0 or 1. one() returns its id when it exists, or null
# when the endpoint is disabled - safer than [0], which errors when the list is
# empty.
output "s3_gateway_endpoint_id" {
  description = "ID of the S3 gateway endpoint, or null when disabled."
  value       = one(aws_vpc_endpoint.s3[*].id)
}
