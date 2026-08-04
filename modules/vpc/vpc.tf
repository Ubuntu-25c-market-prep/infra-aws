###############################################################################
# The VPC itself.
#
# Everything else in this module - gateway, subnets, routing, endpoints - is
# opt-out via a variable, so a caller can take the VPC alone and build the rest
# themselves. Nothing here is hardcoded; the defaults just describe the common
# case.
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames
  instance_tenancy     = var.instance_tenancy

  tags = merge(var.tags, {
    Name = "${var.name}-vpc"
  })
}
