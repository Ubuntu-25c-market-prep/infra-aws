output "id" {
  description = "Bucket name."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "Bucket ARN, for IAM policy resource blocks."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional endpoint. Prefer this over the global domain name, which answers with a redirect for the first few hours after creation."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
