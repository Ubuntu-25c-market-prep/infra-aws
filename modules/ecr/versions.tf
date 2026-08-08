# Provider requirements for the module. No backend and no provider block - the
# calling root supplies those. Pinning ~> 5.70 here keeps standalone validation
# on the same major version the roots use.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}
