# ---------------------------------------------------------------------------
# Detective controls.
#
# The rest of this repository is preventative: it stops bad configurations from
# existing. This module is the other half — it records what actually happened,
# so an incident can be reconstructed and a drifted account can be noticed.
#
#   CloudTrail   — the API audit log. Who called what, from where, when.
#   GuardDuty    — continuous threat detection over CloudTrail/DNS/VPC data.
#   Config       — resource configuration history and drift.
#   Security Hub — aggregates findings against a published benchmark.
#
# All four write into one KMS-encrypted, access-logged S3 bucket.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  # Bucket names are globally unique across all of AWS, so scope to the account.
  # The account ID is resolved at apply time and never written into the repo.
  log_bucket_name    = "${var.name_prefix}-security-logs-${local.account_id}"
  access_bucket_name = "${var.name_prefix}-security-logs-access-${local.account_id}"

  trail_name = "${var.name_prefix}-trail"

}

# ===========================================================================
# KMS — one customer-managed key for all security log data
# ===========================================================================

resource "aws_kms_key" "logs" {
  description             = "${var.name_prefix} security log encryption (CloudTrail, Config)"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.kms.json

  tags = { Name = "${var.name_prefix}-security-logs" }
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name_prefix}-security-logs"
  target_key_id = aws_kms_key.logs.key_id
}

data "aws_iam_policy_document" "kms" {
  # A KMS key policy is attached to the key itself, so `resources = ["*"]`
  # resolves to this one key and cannot be narrowed. The root-account statement
  # is AWS's required key-administration grant — without it the key can become
  # unmanageable. Both are inherent to key policies, not lax scoping.
  #checkov:skip=CKV_AWS_356:Key-policy resource is always "*" (the key itself).
  #checkov:skip=CKV_AWS_109:Root kms:* is AWS's required key-administration grant.
  #checkov:skip=CKV_AWS_111:Root kms:* is AWS's required key-administration grant.
  statement {
    sid       = "EnableAccountKeyAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudTrailEncrypt"
    actions   = ["kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    # Bind the grant to this account's trail so the service principal cannot be
    # induced to use the key on another account's behalf.
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:${local.partition}:cloudtrail:*:${local.account_id}:trail/*"]
    }
  }

  statement {
    sid       = "AllowCloudWatchLogs"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*"]
    }
  }

  statement {
    sid       = "AllowConfigAndS3LogDelivery"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com", "logging.s3.amazonaws.com", "delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# ===========================================================================
# Access-log bucket — receives server access logs from the security log bucket
# ===========================================================================

resource "aws_s3_bucket" "access_logs" {
  bucket        = local.access_bucket_name
  force_destroy = var.force_destroy

  # This IS the access-log destination: logging it to itself would recurse.
  # Replication and event notifications are out of scope for a log sink.
  #checkov:skip=CKV_AWS_18:This is the log-target bucket; self-logging would recurse.
  #checkov:skip=CKV_AWS_144:Single-region reference; replication is out of scope for a log sink.
  #checkov:skip=CKV2_AWS_62:No event-notification consumer for access logs.
  tags = { Name = local.access_bucket_name }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-KMS with a bucket key. S3 server-access-log delivery to a CMK-encrypted
# destination requires the bucket key, and the key policy above grants
# logging.s3.amazonaws.com the GenerateDataKey it needs. Matches the state
# backend's log bucket rather than dropping to SSE-S3 here.
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "access_logs" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.access_logs.arn, "${aws_s3_bucket.access_logs.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "AllowS3LogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:s3:::${local.log_bucket_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = data.aws_iam_policy_document.access_logs.json

  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}

# ===========================================================================
# Security log bucket — CloudTrail and Config both deliver here
# ===========================================================================

resource "aws_s3_bucket" "logs" {
  bucket        = local.log_bucket_name
  force_destroy = var.force_destroy

  # Versioning, lifecycle, and CloudTrail's own log-file validation cover
  # tamper-evidence in one region. Cross-region replication and event
  # notifications are out of scope for this reference.
  #checkov:skip=CKV_AWS_144:Single-region reference; versioning + log validation cover integrity.
  #checkov:skip=CKV2_AWS_62:No event-notification consumer for the log bucket.
  tags = { Name = local.log_bucket_name }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_logging" "logs" {
  bucket        = aws_s3_bucket.logs.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "security-logs-access/"
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-security-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "logs" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_cloudtrail ? [1] : []
    content {
      sid       = "AWSCloudTrailAclCheck"
      effect    = "Allow"
      actions   = ["s3:GetBucketAcl"]
      resources = [aws_s3_bucket.logs.arn]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = ["arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_cloudtrail ? [1] : []
    content {
      sid       = "AWSCloudTrailWrite"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.logs.arn}/cloudtrail/AWSLogs/${local.account_id}/*"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      # bucket-owner-full-control is required by CloudTrail's delivery contract.
      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = ["arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_config ? [1] : []
    content {
      sid       = "AWSConfigAclCheck"
      effect    = "Allow"
      actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
      resources = [aws_s3_bucket.logs.arn]

      principals {
        type        = "Service"
        identifiers = ["config.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_config ? [1] : []
    content {
      sid       = "AWSConfigWrite"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.logs.arn}/config/AWSLogs/${local.account_id}/*"]

      principals {
        type        = "Service"
        identifiers = ["config.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

# ===========================================================================
# CloudTrail — the API audit log
# ===========================================================================

# Streaming to CloudWatch Logs as well as S3 lets you alarm on events in near
# real time rather than waiting for the next S3 delivery (Checkov CKV2_AWS_10).
resource "aws_cloudwatch_log_group" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  # Retention here is the near-real-time alerting window, not the archive:
  # prod keeps 365 days, dev 30. The durable copy lives in S3 under the bucket's
  # own lifecycle, so a shorter CloudWatch window loses no audit evidence.
  #checkov:skip=CKV_AWS_338:CloudWatch is the alerting window; S3 holds the durable audit copy.
  name              = "/aws/cloudtrail/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = { Name = "${var.name_prefix}-trail" }
}

data "aws_iam_policy_document" "trail_assume" {
  count = var.enable_cloudtrail ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  name               = "${var.name_prefix}-cloudtrail-logs"
  assume_role_policy = data.aws_iam_policy_document.trail_assume[0].json
}

data "aws_iam_policy_document" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  statement {
    sid       = "WriteTrailEvents"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.trail[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  name   = "${var.name_prefix}-cloudtrail-logs"
  role   = aws_iam_role.trail[0].id
  policy = data.aws_iam_policy_document.trail[0].json
}

resource "aws_cloudtrail" "this" {
  count = var.enable_cloudtrail ? 1 : 0

  # CKV2_AWS_10 wants CloudTrail wired to CloudWatch Logs — it is, three lines
  # below. The graph check cannot follow `aws_cloudwatch_log_group.trail[0].arn`
  # through the count index; the same config without `count` passes the check.
  #checkov:skip=CKV2_AWS_10:CloudWatch integration IS configured; graph check can't resolve the count index.
  # No SNS topic: alerting runs off the CloudWatch Logs stream and EventBridge,
  # where it can be filtered. A notification per log-file delivery is volume,
  # not signal.
  #checkov:skip=CKV_AWS_252:Alerting is via CloudWatch Logs/EventBridge; per-delivery SNS is noise.
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.logs.id
  s3_key_prefix  = "cloudtrail"

  # A trail an attacker can silently edit is worthless: log file validation
  # writes signed digests so tampering is detectable after the fact.
  enable_log_file_validation = true

  # Global services (IAM, STS, CloudFront) only emit into a multi-region trail.
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_logging                = true

  kms_key_id = aws_kms_key.logs.arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail[0].arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail[0].arn

  tags = { Name = local.trail_name }

  depends_on = [aws_s3_bucket_policy.logs]
}

# ===========================================================================
# GuardDuty — continuous threat detection
# ===========================================================================

resource "aws_guardduty_detector" "this" {
  count = var.enable_guardduty ? 1 : 0

  # CKV2_AWS_3 is satisfied only by an org-wide GuardDuty configuration
  # (aws_guardduty_organization_configuration), which needs AWS Organizations.
  # This is a single-account baseline, so the detector below is the whole of it.
  #checkov:skip=CKV2_AWS_3:Org-wide GuardDuty needs AWS Organizations; out of scope for a single account.
  enable = true

  # Fifteen minutes is the tighter of the two options; the slower setting only
  # exists to reduce noise, and detection latency matters more here.
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = { Name = "${var.name_prefix}-guardduty" }
}

# ===========================================================================
# AWS Config — resource configuration history and drift
# ===========================================================================

data "aws_iam_policy_document" "config_assume" {
  count = var.enable_config ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  count = var.enable_config ? 1 : 0

  name               = "${var.name_prefix}-config"
  assume_role_policy = data.aws_iam_policy_document.config_assume[0].json
}

# AWS-managed policy purpose-built for the Config service role: read-only
# describe/list across services so it can record their configuration.
resource "aws_iam_role_policy_attachment" "config" {
  count = var.enable_config ? 1 : 0

  role       = aws_iam_role.config[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

data "aws_iam_policy_document" "config_delivery" {
  count = var.enable_config ? 1 : 0

  statement {
    sid       = "DeliverConfigSnapshots"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/config/AWSLogs/${local.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid       = "GetBucketAcl"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid       = "EncryptWithLogKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.logs.arn]
  }
}

resource "aws_iam_role_policy" "config_delivery" {
  count = var.enable_config ? 1 : 0

  name   = "${var.name_prefix}-config-delivery"
  role   = aws_iam_role.config[0].id
  policy = data.aws_iam_policy_document.config_delivery[0].json
}

resource "aws_config_configuration_recorder" "this" {
  count = var.enable_config ? 1 : 0

  name     = "${var.name_prefix}-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  count = var.enable_config ? 1 : 0

  name           = "${var.name_prefix}-delivery"
  s3_bucket_name = aws_s3_bucket.logs.id
  s3_key_prefix  = "config"
  s3_kms_key_arn = aws_kms_key.logs.arn

  # The recorder must exist before a delivery channel can reference it.
  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  count = var.enable_config ? 1 : 0

  # CKV2_AWS_45 wants the recorder to cover all supported resource types — it
  # does, via all_supported/include_global_resource_types on the recorder above.
  # The graph check cannot follow the count index; the same config without
  # `count` passes.
  #checkov:skip=CKV2_AWS_45:Recorder sets all_supported=true; graph check can't resolve the count index.
  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true

  # Recording fails unless the channel it delivers to already exists.
  depends_on = [aws_config_delivery_channel.this]
}

# ===========================================================================
# Security Hub — findings aggregated against a published benchmark
# ===========================================================================

resource "aws_securityhub_account" "this" {
  count = var.enable_security_hub ? 1 : 0

  enable_default_standards = false
}

# Subscribe explicitly rather than relying on the default set, so the enabled
# benchmark is visible in code instead of being whatever AWS turns on today.
resource "aws_securityhub_standards_subscription" "foundational" {
  count = var.enable_security_hub ? 1 : 0

  standards_arn = "arn:${local.partition}:securityhub:${local.region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.this]
}
