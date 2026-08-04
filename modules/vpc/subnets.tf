###############################################################################
# Public subnets - one per availability zone.
#
# Neither the zones nor the CIDRs are written into the module. By default the
# zones come from whatever region the caller's provider points at, and the CIDRs
# are carved out of the VPC block; either can be given explicitly instead.
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Explicit zones win; otherwise take the first az_count zones in the region.
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Explicit CIDRs win; otherwise slice the VPC block (newbits 8 on a /16 gives
  # /24s). The list length is what decides how many subnets exist.
  public_subnet_cidrs = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [
    for i in range(var.az_count) : cidrsubnet(var.cidr_block, var.public_subnet_newbits, i)
  ]
}

resource "aws_subnet" "public" {
  count = length(local.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.tags, var.subnet_tags, {
    Name = "${var.name}-public-${count.index}"
  })
}
