# ADR 0002 — GitHub OIDC instead of static AWS keys in CI

**Status:** Accepted

## Context

CI needs AWS access to plan and apply. The traditional approach stores an access
key and secret as repository secrets — long-lived credentials that can leak, get
committed, or be exfiltrated from a compromised runner, and that must be rotated
by hand.

## Decision

Federate GitHub Actions to AWS via OIDC. The workflow exchanges a short-lived
GitHub-signed token for temporary AWS credentials by assuming a role. The role's
trust policy pins the token's `sub` claim to one repository and one branch with
`StringEquals` — never a wildcard.

## Consequences

- **+** No long-lived AWS keys exist to leak or rotate.
- **+** Credentials are minted per run and expire in an hour.
- **+** The trust boundary is explicit and auditable in the trust policy.
- **−** A wildcard in the `sub` condition would silently widen that boundary to
  every repo in the org — or every repo on GitHub. This is called out in the
  module and guarded by using exact-match, not `StringLike`.
- **−** The OIDC provider is account-global, so it is created once and referenced
  by other environments.
