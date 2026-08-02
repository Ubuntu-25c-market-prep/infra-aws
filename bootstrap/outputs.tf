output "state_bucket" {
  description = "Bucket holding Terraform state for every other configuration."
  value       = aws_s3_bucket.tfstate.id
}

output "kms_key_arn" {
  description = "Shared KMS key for state and log encryption."
  value       = aws_kms_key.platform.arn
}

output "backend_config" {
  description = "Paste into the backend block of every other configuration."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.tfstate.id}"
        key          = "<env>/<component>/terraform.tfstate"
        region       = "${var.region}"
        encrypt      = true
        kms_key_id   = "${aws_kms_key.platform.arn}"
        use_lockfile = true
      }
    }
  EOT
}
