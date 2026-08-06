variable "name" {
  description = "Bucket name. Must be globally unique - suffix your account id."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for encryption, from bootstrap's kms_key_arn output."
  type        = string
}

variable "region" {
  description = "Region to create the bucket in."
  type        = string
  default     = "us-east-1"
}
