# ADR 0001 — Remote state in S3 + DynamoDB, created by a one-time bootstrap

**Status:** Accepted

## Context

Terraform state must be shared and locked for any team, and it can contain
secrets, so it needs encryption and recovery. The backend that provides all this
is itself infrastructure — which creates a chicken-and-egg problem (see
[bootstrap.md](../bootstrap.md)).

## Decision

Use an S3 bucket (versioned, SSE-KMS, TLS-only, access-logged) plus a DynamoDB
lock table, provisioned by a dedicated `bootstrap/` module that runs once with
local state and then migrates into the bucket it created.

## Consequences

- **+** State is encrypted, versioned, recoverable, and locked.
- **+** The bootstrap is ordinary Terraform, not a shell script — reviewable and
  reproducible.
- **−** A documented one-time manual step (the state migration). This is
  inherent to the problem, not a shortcut.
- **−** First-apply ordering: the backend must exist before any environment can
  `init`.
