output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, keyed by AZ."
  value       = module.vpc.private_subnet_ids
}

output "database_subnet_ids" {
  description = "Isolated database subnet IDs, keyed by AZ."
  value       = module.vpc.database_subnet_ids
}

output "github_actions_role_arn" {
  description = "Role ARN for the dev GitHub Actions workflow to assume via OIDC."
  value       = module.iam.github_actions_role_arn
}

output "auditor_role_arn" {
  description = "MFA-gated read-only auditor role ARN."
  value       = module.iam.auditor_role_arn
}

output "ec2_instance_profile_name" {
  description = "Instance profile granting SSM Session Manager access."
  value       = module.iam.ec2_instance_profile_name
}

output "security_log_bucket_name" {
  description = "Bucket receiving CloudTrail (and Config, where enabled) data."
  value       = module.detective.log_bucket_name
}

output "cloudtrail_arn" {
  description = "ARN of the environment's CloudTrail trail."
  value       = module.detective.cloudtrail_arn
}
