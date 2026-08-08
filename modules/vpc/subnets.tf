###############################################################################
# Public subnets - one per availability zone.
#
# Nothing here is written into the module: the zones come from whatever region
# the caller's provider points at, and the CIDRs are carved out of the VPC
# block. Only how many (az_count) is a decision the caller makes.
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # newbits 8 on a /16 gives /24s: 10.0.0.0/24, 10.0.1.0/24, ...
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index)
  map_public_ip_on_launch = var.map_public_ip_on_launch

  # subnet_tags carries things only subnets need, like the ELB discovery tag.
  tags = merge(var.subnet_tags, {
    Name = "${var.name}-public-${count.index}"
  })
}
