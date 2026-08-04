###############################################################################
# State moves for making the internet gateway optional.
#
# This layer is already applied. Everything in modules/vpc kept its resource
# name through the file split, so those addresses still match state. The two
# below did not: creating the gateway and its default route is now conditional
# on create_internet_gateway, and a counted resource is addressed with an index
# even when the count is one.
#
# Without these blocks Terraform reads the change as "the old resource is gone,
# a new one is needed" and plans a destroy-and-recreate of the gateway - which
# takes the default route, and the cluster's egress, with it.
#
# `terraform plan` must report only these two moves and zero changes. Remove
# this file once the move has been applied.
###############################################################################

moved {
  from = module.vpc.aws_internet_gateway.main
  to   = module.vpc.aws_internet_gateway.main[0]
}

moved {
  from = module.vpc.aws_route.public_default
  to   = module.vpc.aws_route.public_default[0]
}
