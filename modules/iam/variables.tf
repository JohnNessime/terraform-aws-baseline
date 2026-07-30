variable "name_prefix" {
  description = "Resource name prefix, conventionally module.tags.name_prefix (<project>-<environment>)."
  type        = string
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC
# ---------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub organisation or user that owns the repository allowed to assume the CI role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$", var.github_org))
    error_message = "github_org must be a valid GitHub org/user handle."
  }
}

variable "github_repo" {
  description = "Repository name (without the owner) allowed to assume the CI role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must be a valid GitHub repository name."
  }
}

variable "github_branch" {
  description = "Branch whose workflow runs may assume the CI role. Scopes the OIDC `sub` claim."
  type        = string
  default     = "main"
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC provider. An AWS account permits only one provider per URL, so set false in every environment after the first and pass the shared provider by reference."
  type        = bool
  default     = true
}

variable "github_oidc_thumbprints" {
  description = "Certificate thumbprints for the GitHub OIDC endpoint. IAM now verifies GitHub's token against its own trust store, but the API still requires a value."
  type        = list(string)
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fca",
  ]
}

# Optional least-privilege backend access for the CI role. When a state bucket
# ARN is supplied the role gets exactly the permissions Terraform needs to read
# and lock remote state — and nothing else. Deploy permissions for whatever the
# pipeline manages are layered on by the caller, on purpose.
variable "state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket the CI role may read/write. Null disables the backend policy."
  type        = string
  default     = null
}

variable "state_lock_table_arn" {
  description = "ARN of the DynamoDB state-lock table the CI role may use for locking. Null disables lock-table access."
  type        = string
  default     = null
}

variable "state_kms_key_arn" {
  description = "ARN of the KMS key encrypting remote state, so the CI role can decrypt it. Null disables the grant."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Auditor role
# ---------------------------------------------------------------------------

variable "auditor_principal_arns" {
  description = "IAM principal ARNs permitted to assume the read-only auditor role. Assumption is additionally gated on MFA."
  type        = list(string)

  validation {
    condition     = length(var.auditor_principal_arns) > 0
    error_message = "Provide at least one principal ARN for the auditor role; an empty trust policy is unassumable."
  }
}
