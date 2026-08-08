###############################################################################
# Routing - one shared public route table, default route to the IGW.
#
# A single table for every public subnet: they share the same egress and the
# same routes, so per-subnet tables would be identical copies drifting apart.
#
# The default route is tied to the gateway, so it is created only when one is.
# extra_routes lets a caller add NAT, peering or transit-gateway routes without
# editing this file.
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-public-rt"
  }
}

resource "aws_route" "public_default" {
  count = var.create_internet_gateway ? 1 : 0

  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
}

resource "aws_route" "extra" {
  for_each = var.extra_routes

  route_table_id = aws_route_table.public.id

  destination_cidr_block      = each.value.destination_cidr_block
  destination_ipv6_cidr_block = each.value.destination_ipv6_cidr_block

  # Exactly one target should be set per route; the rest stay null and are
  # omitted from the request.
  gateway_id                = each.value.gateway_id
  nat_gateway_id            = each.value.nat_gateway_id
  transit_gateway_id        = each.value.transit_gateway_id
  vpc_peering_connection_id = each.value.vpc_peering_connection_id
  network_interface_id      = each.value.network_interface_id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
