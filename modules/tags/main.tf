# ---------------------------------------------------------------------------
# Tagging standard
#
# Every taggable resource in this repository inherits these tags via the
# provider-level `default_tags` block. Centralising the schema here means the
# standard is enforced by type validation rather than by code review.
# ---------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"

  mandatory_tags = {
    Project            = var.project
    Environment        = var.environment
    Owner              = var.owner
    CostCenter         = var.cost_center
    DataClassification = var.data_classification
    ComplianceScope    = var.compliance_scope
    ManagedBy          = "terraform"
    Repository         = "terraform-aws-baseline"
  }

  tags = merge(local.mandatory_tags, var.extra_tags)
}
