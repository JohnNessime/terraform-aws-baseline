# ADR 0005 — Detective controls alongside preventative ones

**Status:** Accepted

## Context

Everything else in this repository is preventative: locked security groups,
isolated subnets, scoped IAM, encrypted state. Preventative controls answer
"can this bad thing happen?" They do not answer "did something happen, and what
exactly?"

Without an audit trail, an incident is unreconstructable and drift is invisible.
A baseline that only prevents is half a baseline.

## Decision

Add a `detective` module enabling four controls, all writing to one
KMS-encrypted, versioned, access-logged bucket:

- **CloudTrail** — multi-region, with `enable_log_file_validation` so tampering
  with the audit log is detectable, and dual delivery to S3 (durable retention)
  and CloudWatch Logs (near-real-time alerting).
- **GuardDuty** — continuous threat detection at 15-minute publishing.
- **AWS Config** — configuration history and drift, recording all supported
  resource types.
- **Security Hub** — findings scored against AWS Foundational Security Best
  Practices, subscribed explicitly rather than via `enable_default_standards`
  so the benchmark in force is visible in code.

## Consequences

- **+** Incidents become reconstructable; drift becomes visible.
- **+** Log file validation means the trail is evidence, not just a log.
- **−** This is the module that costs real money. Config's per-configuration-item
  charge with `all_supported = true` is the line item most likely to surprise;
  GuardDuty is usage-based. See the module README for figures.
- **−** GuardDuty, Config, and Security Hub are one-per-account-per-region.
  Prod enables them for the account and dev leaves them off, because this
  reference assumes both may target a single AWS account. In a real
  multi-account setup every account enables all four. CloudTrail is not a
  singleton, so both environments keep their own trail.
- **−** Four Checkov skips live here. Two (`CKV2_AWS_10`, `CKV2_AWS_45`) are the
  graph engine failing to resolve references through a `count` index — verified
  by running the same resources without `count`, where both pass. One
  (`CKV2_AWS_3`) requires org-wide GuardDuty via AWS Organizations. One
  (`CKV_AWS_252`) is a deliberate choice to alert from CloudWatch/EventBridge
  rather than an SNS notification per log-file delivery.
