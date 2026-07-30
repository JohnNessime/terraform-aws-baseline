# Architecture

## Composition

Three reusable modules, composed by thin per-environment roots. The roots
declare no resources of their own — they wire modules together and set the
knobs that differ between dev and prod.

```mermaid
flowchart TD
    subgraph roots["environments/* (composition roots)"]
        dev["dev<br/>single NAT · 7d logs · 2 AZ"]
        prod["prod<br/>per-AZ NAT · 365d logs · 3 AZ"]
    end

    subgraph modules["modules/"]
        tags["tags<br/>mandatory tag schema<br/>+ name_prefix"]
        vpc["vpc<br/>network baseline"]
        iam["iam<br/>OIDC · auditor · SSM"]
    end

    bootstrap["bootstrap<br/>S3 + DynamoDB + KMS<br/>remote state backend"]

    dev --> tags & vpc & iam
    prod --> tags & vpc & iam
    tags -. name_prefix + default_tags .-> vpc
    tags -. name_prefix + default_tags .-> iam
    bootstrap -. state backend .-> dev
    bootstrap -. state backend .-> prod
```

## Network (per environment)

```mermaid
flowchart TB
    igw["Internet Gateway"]

    subgraph vpc["VPC (10.x.0.0/16)"]
        direction TB
        subgraph public["Public subnets (per AZ)"]
            nat["NAT gateway(s)"]
        end
        subgraph private["Private subnets (per AZ)"]
            app["Workloads (egress only)"]
        end
        subgraph database["Database subnets (per AZ)"]
            db["Data stores — no internet route"]
        end
        eps["S3 + DynamoDB<br/>gateway endpoints"]
        flow["Flow Logs → KMS-encrypted<br/>CloudWatch log group"]
        dsg["Default SG: zero rules"]
    end

    internet(("Internet")) <--> igw
    igw <--> public
    app -->|"0.0.0.0/0"| nat --> igw
    private -. free, on-backbone .-> eps
    database -. free, on-backbone .-> eps
    vpc --> flow
```

Key points the diagram encodes:

- **Public → NAT → private → database** is a one-way funnel. The database tier
  has no default route at all: nothing there reaches or is reached from the
  internet.
- **Gateway endpoints** carry S3/DynamoDB traffic (including remote state) on
  the AWS backbone, so it never touches — or is billed by — the NAT gateway.
- **Flow logs** land in a KMS-encrypted log group via a dedicated, scoped IAM
  role.
- The **default security group** is managed with zero rules, so it denies all
  traffic instead of shipping AWS's permissive default.

## Decisions in brief

Each of these has a short ADR under [`decisions/`](decisions/):

| Decision | Rationale | ADR |
|----------|-----------|-----|
| Remote state in S3 + DynamoDB, bootstrapped once | State can't store its own backend's creation | [0001](decisions/0001-remote-state-backend.md) |
| GitHub OIDC instead of static AWS keys in CI | No long-lived credentials to leak or rotate | [0002](decisions/0002-oidc-over-static-keys.md) |
| Single vs per-AZ NAT as an environment toggle | Cost in dev, resilience in prod — an explicit tradeoff | [0003](decisions/0003-single-vs-per-az-nat.md) |
| SSM Session Manager instead of SSH/bastion | Removes port 22, key pairs, and a host to patch | [0004](decisions/0004-ssm-over-ssh.md) |
