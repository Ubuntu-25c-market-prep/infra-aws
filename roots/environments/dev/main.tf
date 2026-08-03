###############################################################################
# dev network - builds the VPC by calling the shared module.
###############################################################################

module "vpc" {
  source = "../../../modules/vpc"

  name       = "u25c-dev"
  cidr_block = var.vpc_cidr

  # Free, and keeps ECR image-layer pulls (stored in S3) off the public path.
  enable_s3_gateway_endpoint = true

  # Lets the AWS Load Balancer Controller discover these subnets for public ELBs.
  subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
}
