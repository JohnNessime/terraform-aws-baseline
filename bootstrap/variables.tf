variable "aws_region" {
  description = "AWS region to create the state backend in."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project identifier, fed to the tags module."
  type        = string
  default     = "baseline"
}

variable "environment" {
  description = "Environment tag for the backend. The state store is shared, prod-critical infrastructure, so it is tagged prod by default."
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Team accountable for the state backend."
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "Cost allocation code for the state backend."
  type        = string
  default     = "CC-0000"
}

variable "state_bucket_name" {
  description = "Name of the S3 state bucket. Null derives a globally-unique name from the prefix and account ID."
  type        = string
  default     = null
}

variable "log_bucket_name" {
  description = "Name of the S3 access-log bucket. Null derives a name from the prefix and account ID."
  type        = string
  default     = null
}

variable "lock_table_name" {
  description = "Name of the DynamoDB state-lock table."
  type        = string
  default     = null
}

variable "noncurrent_version_expiration_days" {
  description = "Days to retain noncurrent state object versions before expiry."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 30
    error_message = "Keep at least 30 days of noncurrent versions to allow state recovery."
  }
}

variable "kms_deletion_window_days" {
  description = "Waiting period before the state KMS key is deleted on destroy."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete non-empty buckets. Keep false in real accounts."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable DynamoDB deletion protection on the lock table. Keep false while the repo is disposable; set true in production."
  type        = bool
  default     = false
}
