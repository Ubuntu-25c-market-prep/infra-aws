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

###############################################################################
# Pod subnets - one per availability zone, used only by the VPC CNI.
#
# The public /24s cannot carry prefix delegation. ENABLE_PREFIX_DELEGATION
# makes the CNI allocate whole /28 blocks, and a /28 has to be entirely free.
# Node primary IPs land in otherwise-empty blocks and spoil them one at a time,
# so 10.0.1.0/24 reached zero free /28s while still reporting 100 free
# addresses - and every pod needing an IP stuck in ContainerCreating with
# "failed to assign an IP address to container".
#
# A /20 holds 256 prefixes, so the CNI stops competing with node IPs for room.
# newbits 4 carves /20s; the index starts at 1 because index 0 (10.0.0.0/20) is
# where the public /24s already sit.
###############################################################################

resource "aws_subnet" "pods" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = cidrsubnet(var.cidr_block, 4, count.index + 1)

  # The CNI's secondary ENIs never need a public IP: pod traffic leaving the
  # VPC is SNATed to the node's primary ENI, which is in a public subnet.
  map_public_ip_on_launch = false

  # Deliberately NOT merged with var.subnet_tags. That carries
  # kubernetes.io/role/elb, which would let the load balancer controller put
  # ELBs in here. karpenter.sh/discovery is absent for the same reason: nodes
  # belong in the public subnets, only pod ENIs belong here.
  #
  # kubernetes.io/role/cni is what ENABLE_SUBNET_DISCOVERY looks for; the CNI
  # picks the tagged subnet in its own AZ with the most free addresses.
  tags = {
    Name                     = "${var.name}-pods-${count.index}"
    "kubernetes.io/role/cni" = "1"
  }
}

# Same public route table as the node subnets - ADR 0005 means there is no NAT,
# and pod ENIs need the VPC-local routes either way.
resource "aws_route_table_association" "pods" {
  count = length(aws_subnet.pods)

  subnet_id      = aws_subnet.pods[count.index].id
  route_table_id = aws_route_table.public.id
}
