# ADR 0004 — SSM Session Manager instead of SSH and bastion hosts

**Status:** Accepted

## Context

Operators sometimes need shell access to EC2 instances. The traditional path is
SSH: open port 22, manage key pairs, and run a bastion host in a public subnet
as the jump point. Every part of that is attack surface — an exposed port, keys
to distribute and revoke, and a host to patch and monitor.

## Decision

Give EC2 instances an instance role carrying only `AmazonSSMManagedInstanceCore`
and use **SSM Session Manager** for access. No inbound SSH, no key pairs, no
bastion.

## Consequences

- **+** Port 22 is never opened; instances can live entirely in private subnets.
- **+** No SSH keys to leak, rotate, or forget to revoke.
- **+** Every session is IAM-authorised and logged — access control and audit
  come for free.
- **+** One less host (the bastion) to run, patch, and pay for.
- **−** Requires the SSM agent on instances (present by default on current Amazon
  Linux / Ubuntu images) and outbound reach to the SSM endpoints — via NAT, or
  interface endpoints if you want to stay fully private.
