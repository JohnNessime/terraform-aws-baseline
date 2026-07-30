# ---------------------------------------------------------------------------
# dev environment — composition only. No resources are declared here directly;
# this root just wires the modules together with dev-appropriate settings.
#
# How dev differs from prod (and why):
#   - single NAT gateway   → one gateway, not one per AZ; ~$32/mo saved, at the
#                            cost of losing private egress if that AZ fails.
#   - 7-day flow log retention → dev traffic isn't kept for a year.
#   - OIDC provider created here → prod references it (account-global resource).
# ---------------------------------------------------------------------------

module "tags" {
  source = "../../modules/tags"

  project             = var.project
  environment         = "dev"
  owner               = var.owner
  cost_center         = var.cost_center
  data_classification = "internal"
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix = module.tags.name_prefix
  vpc_cidr    = var.vpc_cidr
  az_count    = 2

  enable_nat_gateway = true
  single_nat_gateway = true # dev accepts the AZ-failure blast radius to save cost

  enable_flow_logs        = true
  flow_log_retention_days = 7
}

module "iam" {
  source = "../../modules/iam"

  name_prefix = module.tags.name_prefix

  github_org    = var.github_org
  github_repo   = var.github_repo
  github_branch = "develop" # dev CI deploys from the develop branch

  # dev owns the account-global OIDC provider; prod references it.
  create_github_oidc_provider = true

  auditor_principal_arns = var.auditor_principal_arns

  state_bucket_arn     = var.state_bucket_arn
  state_lock_table_arn = var.state_lock_table_arn
  state_kms_key_arn    = var.state_kms_key_arn
}
