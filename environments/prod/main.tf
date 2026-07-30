# ---------------------------------------------------------------------------
# prod environment — composition only, no resources declared directly.
#
# How prod differs from dev (and why):
#   - NAT gateway per AZ    → private egress survives a single-AZ failure;
#                             costs ~$32/mo per AZ, which prod pays for uptime.
#   - 365-day flow log retention → a year of traffic records for audits.
#   - 3 AZs                 → wider fault tolerance.
#   - references the OIDC provider dev created (account-global resource).
# ---------------------------------------------------------------------------

module "tags" {
  source = "../../modules/tags"

  project             = var.project
  environment         = "prod"
  owner               = var.owner
  cost_center         = var.cost_center
  data_classification = "confidential"
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix = module.tags.name_prefix
  vpc_cidr    = var.vpc_cidr
  az_count    = 3

  enable_nat_gateway = true
  single_nat_gateway = false # per-AZ NAT: private egress survives an AZ outage

  enable_flow_logs        = true
  flow_log_retention_days = 365
}

module "iam" {
  source = "../../modules/iam"

  name_prefix = module.tags.name_prefix

  github_org    = var.github_org
  github_repo   = var.github_repo
  github_branch = "main" # prod CI deploys from main only

  # The OIDC provider is account-global and already created by dev; reference it.
  create_github_oidc_provider = false

  auditor_principal_arns = var.auditor_principal_arns

  state_bucket_arn     = var.state_bucket_arn
  state_lock_table_arn = var.state_lock_table_arn
  state_kms_key_arn    = var.state_kms_key_arn
}
