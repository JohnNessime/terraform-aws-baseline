variable "project" {
  description = "Project or product identifier. Lowercase alphanumeric and hyphens only."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project))
    error_message = "project must be 3-32 chars, lowercase alphanumeric or hyphen, and cannot start/end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Team or distribution list accountable for the resources (e.g. 'platform-team')."
  type        = string
}

variable "cost_center" {
  description = "Cost allocation code used for chargeback reporting."
  type        = string
}

variable "data_classification" {
  description = "Sensitivity of data handled by the resources."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be one of: public, internal, confidential, restricted."
  }
}

variable "compliance_scope" {
  description = "Compliance regime the resources fall under, or 'none'."
  type        = string
  default     = "none"
}

variable "extra_tags" {
  description = "Additional free-form tags merged on top of the mandatory tag set."
  type        = map(string)
  default     = {}
}
