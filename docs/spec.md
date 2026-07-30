# Project specification

The engineering contract for this repository: what it contains, what must never
happen, and how "done" is defined. Read this before opening a PR.

**Audience for the finished repo:** hiring managers and DevOps interviewers.
Optimise for *legibility of engineering judgement*, not feature count. A
reviewer spends four minutes here — the README and the CI badge do most of the
talking.

---

## 1. Non-negotiables

These are hard failures, not preferences.

| Rule | Why |
|------|-----|
| No AWS account IDs anywhere — not in ARNs, examples, docs, or comments | Account IDs are a recon primitive |
| No real ARNs. Use `arn:aws:iam::123456789012:role/Example` as the placeholder | Same |
| No access keys, secret keys, session tokens, PATs, or `.pem` content | Obvious |
| No real domain names, emails, IPs, or hostnames | This is a public repository |
| No `*.tfstate`, `*.tfvars`, `*.tfplan` committed | State and plans leak resource attributes and sometimes plaintext passwords |
| No real CIDR blocks from any live network | Use RFC 1918 documentation ranges only |
| CI must never require AWS credentials | `fmt`, `validate`, `tflint`, `checkov` are all static — they run with zero cloud access |

`.gitignore` and the `gitleaks` pre-commit hook enforce most of this
mechanically. Do not weaken either. Before pushing:

```bash
pre-commit install
pre-commit run --all-files
gitleaks detect --source . --log-opts=--all --redact
```

---

## 2. Layout

```
terraform-aws-baseline/
├── README.md                      # the deliverable reviewers actually read
├── LICENSE                        # MIT
├── Makefile                       # make fmt / validate / lint / scan / all
├── .gitignore .gitattributes .pre-commit-config.yaml
├── .tflint.hcl .checkov.yaml
├── .github/
│   ├── workflows/ci.yml           # fmt, validate, tflint, gitleaks
│   ├── workflows/checkov.yml      # checkov + SARIF (separate, for its own badge)
│   ├── dependabot.yml             # terraform + github-actions ecosystems
│   └── pull_request_template.md
├── docs/
│   ├── spec.md                    # this file
│   ├── architecture.md            # diagrams + decisions
│   ├── bootstrap.md               # the chicken-and-egg state problem
│   ├── tagging-standards.md
│   └── decisions/                 # ADR-0001..N, short
├── bootstrap/                     # run ONCE, local state, then migrate
├── modules/{tags,vpc,iam}/
└── environments/{dev,prod}/
```

Every module directory gets `versions.tf`, `variables.tf`, `main.tf`,
`outputs.tf`, and `README.md`. No exceptions — the uniformity is part of the
signal.

---

## 3. Conventions

- `required_version = ">= 1.6.0"`; AWS provider pinned `~> 5.70`. Dependabot is
  configured to ignore **major** provider bumps: 6.x is a migration to plan, not
  a dependency PR to merge.
- Resource names use `local.name_prefix` from the `tags` module:
  `<project>-<env>-<resource>`.
- Every `variable` has a `description` and an explicit `type`. Enums and formats
  get `validation` blocks — push errors to plan time, not apply time.
- Every `output` has a `description`. Mark anything sensitive `sensitive = true`.
- No `count` where `for_each` expresses intent better.
- The dependency lock file belongs to **root** modules (`bootstrap/`,
  `environments/*`) and is generated multi-platform so CI can verify on Linux.
  Reusable modules under `modules/` do not commit one.
- Comment the *why*, never the *what*. `# NAT per-AZ costs ~$32/mo each; dev
  uses a single NAT and accepts the AZ-failure blast radius` is worth writing.
  `# create NAT gateway` is not.

---

## 4. Module contracts

### 4.1 `modules/tags` — complete

Centralises the mandatory tag schema and exposes `tags`, `mandatory_tags`, and
`name_prefix`. Root modules feed `module.tags.tags` into the provider's
`default_tags` block so every taggable resource inherits them. Do not duplicate
tag maps on individual resources.

### 4.2 `modules/vpc`

Multi-AZ VPC. Inputs: `vpc_cidr`, `az_count`, `enable_nat_gateway`,
`single_nat_gateway`, `enable_flow_logs`, `flow_log_retention_days`.

- Public / private / database subnet tiers, derived with `cidrsubnet()` rather
  than hardcoded — show the maths, not a magic list.
- IGW; NAT gateways with per-AZ vs single toggle (cost/resilience tradeoff).
- Route tables per tier and per AZ.
- **VPC Flow Logs** to CloudWatch with a dedicated IAM role and KMS-encrypted log
  group (Checkov `CKV2_AWS_11`).
- **Default security group locked down** — zero ingress, zero egress
  (`CKV2_AWS_12`).
- S3 and DynamoDB **gateway VPC endpoints** — free, and keeps state traffic off
  the NAT.
- Database subnets with **no route to the internet at all**.

### 4.3 `modules/iam`

The least-privilege showcase. Three constructs:

1. **GitHub Actions OIDC provider + role.** The centrepiece. No long-lived AWS
   keys in CI. The trust policy scopes
   `token.actions.githubusercontent.com:sub` to a specific
   `repo:<owner>/<repo>:ref:refs/heads/<branch>` with `StringEquals` — not
   `repo:<owner>/*`, and never `*`. A wildcard `sub` lets *any* matching GitHub
   repo assume the role; that constraint is the whole point of the module.
2. **Read-only auditor role** with `SecurityAudit` + `ViewOnlyAccess`, assumable
   only by a principal passed in as a variable, gated on
   `aws:MultiFactorAuthPresent`.
3. **EC2 instance role** with `AmazonSSMManagedInstanceCore` only — SSM Session
   Manager replaces SSH and bastion hosts entirely.

Policies are built with `data.aws_iam_policy_document`, never inline JSON
heredocs. No `Action = "*"`. No `Resource = "*"` except where AWS genuinely
requires it — and where it does, add a `condition` and a comment saying why.

### 4.4 `bootstrap/`

Solves the chicken-and-egg problem: the S3 backend can't store its own creation.
Runs once with local state, then the state migrates into the bucket it just
made. See [`bootstrap.md`](bootstrap.md).

Creates an S3 state bucket (versioning, SSE-KMS with a customer-managed key,
all four public-access-block flags, TLS-only bucket policy, access logging to a
separate log bucket, noncurrent-version expiry), a DynamoDB lock table
(`LockID` hash key, `PAY_PER_REQUEST`, PITR, SSE), and a KMS key with rotation
enabled and a scoped key policy.

### 4.5 `environments/dev` and `environments/prod`

Thin root modules — composition only, no resources declared directly. Each has
`backend.tf` (partial S3 config), `providers.tf` with `default_tags`, `main.tf`
wiring the modules, and `terraform.tfvars.example`.

Dev and prod must differ *meaningfully*, and the diff should be defensible:
single NAT and 7-day flow log retention in dev; per-AZ NAT and 365-day retention
in prod. Identical environments would suggest the code had never been run.

---

## 5. CI

Triggers on push to `main` and all PRs. No AWS credentials, no `terraform plan`.

`ci.yml`:
- `fmt` — `terraform fmt -check -recursive -diff`
- `validate` — matrix over every module and environment dir
- `tflint` — with `.tflint.hcl`, AWS ruleset plugin enabled
- `gitleaks` — pinned binary running `detect --log-opts=--all`, a genuine
  full-history scan. Deliberately *not* `gitleaks-action`, which only scans the
  commits in a push event and fails outright on a repository's first push.

`checkov.yml` runs Checkov separately with SARIF uploaded to GitHub code
scanning. It is its own workflow so it carries its own status badge — a badge
is only worth showing if it can go red.

Pin every action to a **commit SHA**, not a tag. Tags are mutable; SHA-pinning
is supply-chain hygiene.

Checkov will flag things. Fix what's real. For anything genuinely not
applicable, use an inline `#checkov:skip=CKV_AWS_XXX:<reason>` with a real
reason. Never add a blanket skip list to `.checkov.yaml` — an empty skip list is
a stronger signal than a green badge.

---

## 6. README requirements

The README is the deliverable:

1. One-sentence statement of what this is and the problem it solves.
2. CI + Checkov badges, immediately visible.
3. Architecture diagram — Mermaid, renders natively on GitHub, no image files.
4. **Security decisions** — OIDC instead of static keys; scoped trust policy;
   encrypted + versioned + TLS-only state; locked default SG; isolated DB
   subnets; SSM instead of SSH. Two lines each: decision, then rationale.
5. Quickstart: bootstrap → migrate state → `make all` → apply dev.
6. Cost note: what this costs to run (NAT gateways dominate) and how to destroy
   it.
7. **What I'd add next** — honest scope boundaries. A stated limitation earns
   more trust than an implied claim of completeness.

Never claim this is running in production or that it has served real traffic. It
is a reference implementation, and saying so plainly is the stronger move.

---

## 7. Definition of done

```bash
make all          # fmt + validate + tflint + checkov, all clean
pre-commit run --all-files
```

`terraform init -backend=false && terraform validate` passes in every module and
both environments. The README renders correctly and the Mermaid diagrams
display. No secret-shaped string anywhere in history.

Commits follow Conventional Commits (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`).
Squash nothing — a readable commit history showing the build order is itself
part of what's being demonstrated.
