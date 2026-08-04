###############################################################################
# Internet gateway - the egress path for the public subnets.
#
# Opt-out: set create_internet_gateway = false for a VPC with no route to the
# internet. The default route in route-table.tf disappears with it.
###############################################################################

resource "aws_internet_gateway" "main" {
  count = var.create_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}
