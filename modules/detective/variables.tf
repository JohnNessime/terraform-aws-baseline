variable "name_prefix" {
  description = "Resource name prefix, conventionally module.tags.name_prefix (<project>-<environment>)."
  type        = string
}

# ---------------------------------------------------------------------------
# Per-service toggles.
#
# CloudTrail is NOT an account singleton — several trails can coexist, so each
# environment can safely run its own. GuardDuty, Config, and Security Hub ARE
# one-per-account-per-region: enabling them from two root modules that target
# the same AWS account will fail on the second apply. Leave them on in the
# account's primary environment and off elsewhere.
# ---------------------------------------------------------------------------

variable "enable_cloudtrail" {
  description = "Record management and global service events to a multi-region CloudTrail."
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Enable GuardDuty threat detection. Account-global: enable from one environment per AWS account."
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config recording. Account-global: enable from one environment per AWS account."
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Enable Security Hub with the AWS Foundational Security Best Practices standard. Account-global: enable from one environment per AWS account."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retention for the CloudTrail CloudWatch log group. Must be a value CloudWatch Logs accepts."
  type        = number
  default     = 365

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs supports (e.g. 7, 30, 90, 365)."
  }
}

variable "log_expiration_days" {
  description = "Days before objects in the security log bucket expire. Audit evidence is usually kept at least a year."
  type        = number
  default     = 365

  validation {
    condition     = var.log_expiration_days >= 90
    error_message = "Keep security logs for at least 90 days; shorter retention defeats the point of recording them."
  }
}

variable "kms_deletion_window_days" {
  description = "Waiting period before the security-log KMS key is deleted on destroy."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete non-empty log buckets. Keep false in real accounts."
  type        = bool
  default     = false
}
