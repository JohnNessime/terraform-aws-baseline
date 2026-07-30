# `tags` module

Single source of truth for the organisation's tagging standard.

Rather than repeating a `tags = { ... }` block on every resource, each root
module instantiates this module once and passes the result to the AWS
provider's `default_tags` block. Every taggable resource then inherits the
full set automatically, and drift is impossible.

## Mandatory tags

| Tag | Purpose | Validated |
|-----|---------|-----------|
| `Project` | Groups resources by product | Regex |
| `Environment` | `dev` / `staging` / `prod` | Enum |
| `Owner` | Accountable team | Required |
| `CostCenter` | Chargeback allocation | Required |
| `DataClassification` | `public` / `internal` / `confidential` / `restricted` | Enum |
| `ComplianceScope` | Regime, or `none` | Default |
| `ManagedBy` | Always `terraform` — flags click-ops drift | Fixed |
| `Repository` | Where the code lives | Fixed |

## Usage

```hcl
module "tags" {
  source = "../../modules/tags"

  project     = "baseline"
  environment = "dev"
  owner       = "platform-team"
  cost_center = "CC-1001"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = module.tags.tags
  }
}
```
