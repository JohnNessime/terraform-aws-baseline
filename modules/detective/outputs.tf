output "log_bucket_name" {
  description = "Name of the S3 bucket receiving CloudTrail and Config data."
  value       = aws_s3_bucket.logs.id
}

output "log_bucket_arn" {
  description = "ARN of the security log bucket."
  value       = aws_s3_bucket.logs.arn
}

output "access_log_bucket_name" {
  description = "Name of the bucket holding S3 server access logs for the security log bucket."
  value       = aws_s3_bucket.access_logs.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting security log data."
  value       = aws_kms_key.logs.arn
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail, or null when disabled."
  value       = var.enable_cloudtrail ? aws_cloudtrail.this[0].arn : null
}

output "cloudtrail_log_group_name" {
  description = "CloudWatch log group receiving trail events, or null when CloudTrail is disabled."
  value       = var.enable_cloudtrail ? aws_cloudwatch_log_group.trail[0].name : null
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector, or null when disabled."
  value       = var.enable_guardduty ? aws_guardduty_detector.this[0].id : null
}

output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder, or null when disabled."
  value       = var.enable_config ? aws_config_configuration_recorder.this[0].name : null
}
