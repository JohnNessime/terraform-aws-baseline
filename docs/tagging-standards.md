# Tagging standards

Tags are how you answer "what is this, who owns it, and who pays for it" months
after the `apply`. This repo enforces one schema, in one place: the
[`tags`](../modules/tags/README.md) module.

## How it's enforced

Each root module instantiates `tags` once and feeds the result into the AWS
provider's `default_tags` block:

```hcl
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = module.tags.tags
  }
}
```

Every taggable resource then inherits the full set automatically. There are **no
per-resource `tags = { ... }` maps** to drift out of sync — the only per-resource
tag anything sets is `Name`, which is inherently unique.

The schema is enforced by *type*, not by review: `environment` and
`data_classification` are validated against enums, `project` against a regex.
A bad value fails at plan time, not in a dashboard three weeks later.

## The mandatory tags

| Tag | Meaning | Enforcement |
|-----|---------|-------------|
| `Project` | Groups resources by product | Regex validation |
| `Environment` | `dev` / `staging` / `prod` | Enum validation |
| `Owner` | Accountable team or list | Required |
| `CostCenter` | Chargeback allocation | Required |
| `DataClassification` | `public` / `internal` / `confidential` / `restricted` | Enum, default `internal` |
| `ComplianceScope` | Regime, or `none` | Default `none` |
| `ManagedBy` | Always `terraform` — flags click-ops drift | Fixed |
| `Repository` | Where the code lives | Fixed |

`ManagedBy = terraform` is quietly one of the most useful: anything in the
account *without* it was created by hand, and that's usually the first thing
worth investigating.

## Naming

Resource names use `module.tags.name_prefix`, which is `<project>-<environment>`.
So a dev VPC's resources are `baseline-dev-*` and prod's are `baseline-prod-*` —
sortable, greppable, and unambiguous across environments.

## Extending

Pass `extra_tags` to add free-form tags on top of the mandatory set for a given
environment; they merge over (never replace) the required ones.
