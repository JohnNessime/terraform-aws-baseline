output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (created or referenced)."
  value       = local.github_oidc_provider_arn
}

output "github_actions_role_arn" {
  description = "ARN of the role GitHub Actions assumes via OIDC. Set this as the workflow's role-to-assume."
  value       = aws_iam_role.github_actions.arn
}

output "auditor_role_arn" {
  description = "ARN of the MFA-gated, read-only auditor role."
  value       = aws_iam_role.auditor.arn
}

output "ec2_instance_role_arn" {
  description = "ARN of the EC2 instance role (SSM Session Manager only)."
  value       = aws_iam_role.ec2_instance.arn
}

output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile to attach to instances for SSM access."
  value       = aws_iam_instance_profile.ec2_instance.name
}
