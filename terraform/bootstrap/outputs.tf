output "state_bucket_name" {
  value       = aws_s3_bucket.state.bucket
  description = "Use this in terraform/platform/backend.hcl"
}

output "state_kms_key_arn" {
  value       = aws_kms_key.state.arn
  description = "KMS key ARN for backend encryption"
}
