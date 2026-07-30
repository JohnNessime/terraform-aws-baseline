# ADR 0003 — Single vs per-AZ NAT as an environment toggle

**Status:** Accepted

## Context

Private subnets reach the internet outbound through a NAT gateway. A NAT gateway
costs roughly \$32/month plus data processing, and it lives in one AZ. You can
run one shared NAT for the whole VPC, or one per AZ.

- **One shared NAT** is cheaper, but if its AZ fails, *every* private subnet
  loses egress.
- **One NAT per AZ** removes that single point of failure but multiplies the
  cost by the number of AZs.

## Decision

Expose it as `single_nat_gateway` on the `vpc` module and set it per environment:

- **dev:** `single_nat_gateway = true` — accept the AZ-failure blast radius to
  save money on an environment that can tolerate downtime.
- **prod:** `single_nat_gateway = false` — pay for per-AZ NAT so egress survives
  a single-AZ outage.

## Consequences

- **+** The cost/resilience tradeoff is explicit, per environment, and defensible
  in review.
- **+** dev and prod differ in a way that proves the code has actually been run
  both ways.
- **−** Gateway VPC endpoints for S3/DynamoDB partly offset NAT cost by keeping
  that traffic off the NAT entirely — worth remembering when sizing.
