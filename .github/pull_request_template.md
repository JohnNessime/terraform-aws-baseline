## What & why

<!-- One or two sentences: what this changes and the problem it solves. -->

## Checklist

- [ ] `make all` passes locally (fmt, validate, tflint, checkov)
- [ ] New variables have a `description`, an explicit `type`, and `validation` where a format or enum applies
- [ ] New outputs have a `description`; anything sensitive is marked `sensitive = true`
- [ ] Any `checkov:skip` added has a real, specific reason inline — no blanket skips
- [ ] No account IDs, real ARNs, CIDRs from live networks, or secret-shaped strings
- [ ] Cost/resilience tradeoffs (NAT, retention, AZ count) are intentional and noted

## Notes for the reviewer

<!-- Anything non-obvious: a tradeoff you made, a skip you added, a follow-up you deferred. -->
