output "state_bucket_name" {
  description = "Name of the S3 state bucket. Use as `bucket` in each environment's backend.tf."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 state bucket, for scoping the CI role's state access."
  value       = aws_s3_bucket.state.arn
}

output "log_bucket_name" {
  description = "Name of the S3 access-log bucket."
  value       = aws_s3_bucket.logs.id
}

output "lock_table_name" {
  description = "Name of the DynamoDB lock table. Use as `dynamodb_table` in backend.tf."
  value       = aws_dynamodb_table.lock.name
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB lock table, for scoping the CI role's lock access."
  value       = aws_dynamodb_table.lock.arn
}

output "kms_key_arn" {
  description = "ARN of the state-encryption KMS key. Use as `kms_key_id` in backend.tf."
  value       = aws_kms_key.state.arn
}

output "kms_key_alias" {
  description = "Alias of the state-encryption KMS key."
  value       = aws_kms_alias.state.name
}

output "region" {
  description = "Region the backend lives in. Use as `region` in backend.tf."
  value       = var.aws_region
}
