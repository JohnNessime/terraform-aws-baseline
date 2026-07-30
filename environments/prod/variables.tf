variable "aws_region" {
  description = "AWS region for the prod environment."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project identifier, fed to the tags module."
  type        = string
  default     = "baseline"
}

variable "owner" {
  description = "Team accountable for the prod environment."
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "Cost allocation code for the prod environment."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the prod VPC. Use an RFC 1918 documentation range."
  type        = string
  default     = "10.20.0.0/16"
}

variable "github_org" {
  description = "GitHub org/user allowed to assume the CI role."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the CI role."
  type        = string
}

variable "auditor_principal_arns" {
  description = "Principal ARNs permitted to assume the read-only auditor role (MFA-gated)."
  type        = list(string)
}

# Optional wiring for the CI role's remote-state permissions. Populate from the
# bootstrap outputs to grant the prod CI role scoped state access.
variable "state_bucket_arn" {
  description = "ARN of the Terraform state bucket (bootstrap output). Null skips the CI state policy."
  type        = string
  default     = null
}

variable "state_lock_table_arn" {
  description = "ARN of the DynamoDB lock table (bootstrap output)."
  type        = string
  default     = null
}

variable "state_kms_key_arn" {
  description = "ARN of the state KMS key (bootstrap output)."
  type        = string
  default     = null
}
