###############################################################################
# S3 gateway endpoint (opt-in, free).
#
# Gateway type, so it is a route-table entry rather than an ENI - no hourly cost
# and no data-processing charge. Associated with the public route table so S3
# and ECR-layer traffic leaves via the endpoint instead of the internet.
#
# The region comes from the provider the caller passes in, not from a literal.
###############################################################################

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]

  tags = merge(var.tags, {
    Name = "${var.name}-s3-endpoint"
  })
}
