data "aws_region" "current" {}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = {
    Name = "${var.name}-vpc"
  }
}

###############################################################################
# Internet gateway - the only egress path in this topology
###############################################################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-igw"
  }
}

###############################################################################
# Public subnets - one per AZ
###############################################################################

resource "aws_subnet" "public" {
  # Two public subnets (ADR 0006). count.index is the loop counter: 0, then 1.
  # cidrsubnet slices the VPC block into /24s; the letter list picks the AZ.
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index)
  availability_zone       = "us-east-1${["a", "b"][count.index]}"
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.subnet_tags, {
    Name = "${var.name}-public-${count.index}"
  })
}

###############################################################################
# Routing - one shared public route table, default route to the IGW
#
# A single table for every public subnet: they share the same egress and the
# same routes, so per-subnet tables would be identical copies drifting apart.
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-public-rt"
  }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# S3 gateway endpoint (opt-in, free)
#
# Gateway type, so it is a route-table entry rather than an ENI - no hourly cost
# and no data-processing charge. Associated with the public route table so S3
# and ECR-layer traffic leaves via the endpoint instead of the internet.
###############################################################################

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]

  tags = {
    Name = "${var.name}-s3-endpoint"
  }
}
