# ---------------------------------------------------------------------------
# Multi-AZ VPC
#
# Three subnet tiers per AZ:
#   public   — routes to the Internet Gateway
#   private  — egress only, via NAT
#   database — no route off the VPC at all (see the deliberately empty RT below)
#
# Subnet CIDRs are *derived*, not hardcoded: cidrsubnet() slices the VPC into
# /20 blocks (newbits = 4 → 16 blocks in a /16) and hands each tier its own
# band of blocks. Change vpc_cidr or az_count and the plan re-derives cleanly.
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"

  # Local Zones / Wavelength report as "available" but reject normal subnets;
  # opt-in-not-required keeps us to the standard regional AZs.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Tier bands: public occupies blocks 0..2, private 4..6, database 8..10.
  # The gap between bands (4) leaves each tier room to grow without collision.
  public_subnets   = { for idx, az in local.azs : az => cidrsubnet(var.vpc_cidr, 4, idx) }
  private_subnets  = { for idx, az in local.azs : az => cidrsubnet(var.vpc_cidr, 4, idx + 4) }
  database_subnets = { for idx, az in local.azs : az => cidrsubnet(var.vpc_cidr, 4, idx + 8) }

  # Which AZs actually get a NAT gateway. single_nat_gateway collapses this to
  # the first AZ; every private route table then points at that one gateway.
  nat_gateway_azs = var.enable_nat_gateway ? (var.single_nat_gateway ? [local.azs[0]] : local.azs) : []

  # Maps each AZ to the AZ whose NAT gateway it should egress through.
  nat_az_for = var.single_nat_gateway ? { for az in local.azs : az => local.azs[0] } : { for az in local.azs : az => az }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name_prefix }
}

# CKV2_AWS_12: the default SG is created implicitly by AWS with allow-all-egress
# and intra-SG ingress. Managing it here with no rules leaves it locked shut, so
# nothing accidentally attaches to a permissive default.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  # No ingress or egress blocks == deny all. This is intentional, not an omission.
  tags = { Name = "${var.name_prefix}-default-locked" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-igw" }
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  # A public subnet is public by definition; instances here need a routable IP.
  #checkov:skip=CKV_AWS_130:Public tier intentionally auto-assigns public IPs.
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-public-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name_prefix}-private-${each.key}" }
}

resource "aws_subnet" "database" {
  for_each = local.database_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name_prefix}-database-${each.key}" }
}

# ---------------------------------------------------------------------------
# NAT gateways — one EIP + gateway per AZ in local.nat_gateway_azs
# ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  for_each = toset(local.nat_gateway_azs)

  domain = "vpc"

  tags = { Name = "${var.name_prefix}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_gateway_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = { Name = "${var.name_prefix}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Route tables — one per tier per AZ
# ---------------------------------------------------------------------------

resource "aws_route_table" "public" {
  for_each = local.public_subnets

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-public-${each.key}" }
}

resource "aws_route" "public_internet" {
  for_each = aws_route_table.public

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[each.key].id
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-private-${each.key}" }
}

# Private egress route only exists when NAT is enabled; otherwise the private
# tier is as isolated as the database tier.
resource "aws_route" "private_nat" {
  for_each = var.enable_nat_gateway ? local.private_subnets : {}

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.nat_az_for[each.key]].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# Database route tables carry no default route on purpose — the database tier
# has no path to the internet, inbound or outbound. Traffic to AWS services
# still works via the gateway endpoints below.
resource "aws_route_table" "database" {
  for_each = local.database_subnets

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-database-${each.key}" }
}

resource "aws_route_table_association" "database" {
  for_each = aws_subnet.database

  subnet_id      = each.value.id
  route_table_id = aws_route_table.database[each.key].id
}

# ---------------------------------------------------------------------------
# Gateway VPC endpoints — S3 and DynamoDB
#
# Gateway endpoints are free and keep S3/DynamoDB traffic (Terraform state,
# among other things) on the AWS backbone instead of routing it out through the
# NAT gateway, where it would incur per-GB data processing charges.
# ---------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [for rt in aws_route_table.private : rt.id],
    [for rt in aws_route_table.database : rt.id],
  )

  tags = { Name = "${var.name_prefix}-s3-endpoint" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [for rt in aws_route_table.private : rt.id],
    [for rt in aws_route_table.database : rt.id],
  )

  tags = { Name = "${var.name_prefix}-dynamodb-endpoint" }
}

# ---------------------------------------------------------------------------
# VPC Flow Logs → KMS-encrypted CloudWatch log group (CKV2_AWS_11)
# ---------------------------------------------------------------------------

# Dedicated CMK for the log group. CloudWatch Logs needs kms:Encrypt/Decrypt via
# the service principal, scoped by encryption context to this account's log ARNs.
resource "aws_kms_key" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  description             = "${var.name_prefix} VPC flow log encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.flow_log_kms[0].json

  tags = { Name = "${var.name_prefix}-flow-log-kms" }
}

resource "aws_kms_alias" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name          = "alias/${var.name_prefix}-flow-log"
  target_key_id = aws_kms_key.flow_log[0].key_id
}

data "aws_iam_policy_document" "flow_log_kms" {
  count = var.enable_flow_logs ? 1 : 0

  # A KMS *key policy* is attached to the key itself, so `resources = ["*"]`
  # resolves to this one key — you cannot reference the key's own ARN here. The
  # root-account admin statement (kms:*) is AWS's required break-glass grant;
  # dropping it can orphan the key. Both are unavoidable for a key policy, hence
  # the scoped skips rather than a weaker policy.
  #checkov:skip=CKV_AWS_356:Key-policy resource is always "*" (the key itself).
  #checkov:skip=CKV_AWS_109:Root kms:* is AWS's required key-administration grant.
  #checkov:skip=CKV_AWS_111:Root kms:* is AWS's required key-administration grant.

  # Account root keeps administrative control of the key (break-glass, rotation
  # policy) so the key never becomes orphaned.
  statement {
    sid       = "EnableAccountKeyAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "AllowCloudWatchLogs"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }

    # Bind the grant to this account's log groups only, so the service principal
    # cannot be tricked into using the key for another account's logs.
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_cloudwatch_log_group" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  # Retention is a per-environment cost/forensics tradeoff set by the caller:
  # prod keeps 365 days, dev accepts 7 to hold down CloudWatch storage cost.
  # CKV_AWS_338 wants a fixed >= 1 year, which would remove that lever.
  #checkov:skip=CKV_AWS_338:Retention is environment-driven; prod=365d, dev=7d by design.
  name              = "/aws/vpc-flow-log/${var.name_prefix}"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = aws_kms_key.flow_log[0].arn

  tags = { Name = "${var.name_prefix}-flow-log" }
}

data "aws_iam_policy_document" "flow_log_assume" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.name_prefix}-flow-log"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume[0].json
}

data "aws_iam_policy_document" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    sid = "WriteFlowLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    # Scoped to this flow log group and its streams, not "*".
    resources = [
      aws_cloudwatch_log_group.flow_log[0].arn,
      "${aws_cloudwatch_log_group.flow_log[0].arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "${var.name_prefix}-flow-log"
  role   = aws_iam_role.flow_log[0].id
  policy = data.aws_iam_policy_document.flow_log[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_log[0].arn
  iam_role_arn             = aws_iam_role.flow_log[0].arn
  max_aggregation_interval = 60

  tags = { Name = "${var.name_prefix}-flow-log" }
}
