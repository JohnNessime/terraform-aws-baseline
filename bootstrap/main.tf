# ---------------------------------------------------------------------------
# Bootstrap — the Terraform state backend, created once with local state.
#
# This is the chicken-and-egg module: the S3 bucket and DynamoDB table that
# hold remote state cannot themselves be stored in that state before they
# exist. So bootstrap runs locally, then its own state is migrated into the
# bucket it just made (docs/bootstrap.md walks through the migration).
# ---------------------------------------------------------------------------

module "tags" {
  source = "../modules/tags"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  cost_center = var.cost_center
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = module.tags.name_prefix

  # Bucket names are globally unique across all of AWS, so scope them to the
  # account. The account ID is resolved at apply time — it is never written into
  # the repository.
  state_bucket_name = coalesce(var.state_bucket_name, "${local.name_prefix}-tfstate-${data.aws_caller_identity.current.account_id}")
  log_bucket_name   = coalesce(var.log_bucket_name, "${local.name_prefix}-tfstate-logs-${data.aws_caller_identity.current.account_id}")
  lock_table_name   = coalesce(var.lock_table_name, "${local.name_prefix}-tflock")
}

# ===========================================================================
# KMS — customer-managed key for state-at-rest and lock-table encryption
# ===========================================================================

resource "aws_kms_key" "state" {
  description             = "${local.name_prefix} Terraform state encryption"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.state_kms.json

  tags = { Name = "${local.name_prefix}-tfstate" }
}

resource "aws_kms_alias" "state" {
  name          = "alias/${local.name_prefix}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

data "aws_iam_policy_document" "state_kms" {
  # In a KMS key policy the resource is always the key the policy is attached
  # to, so `resources = ["*"]` means "this key" and cannot be narrowed. The
  # root-account grant is AWS's required key-administration statement — without
  # it the key can become unmanageable. Both are inherent to key policies.
  #checkov:skip=CKV_AWS_356:Key-policy resource is always "*" (the key itself).
  #checkov:skip=CKV_AWS_109:Root kms:* is AWS's required key-administration grant.
  #checkov:skip=CKV_AWS_111:Root kms:* is AWS's required key-administration grant.
  statement {
    sid       = "EnableAccountKeyAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # S3 server-access-log delivery writes encrypted objects into the log bucket
  # and needs to mint data keys to do so. Scoped to this account.
  statement {
    sid    = "AllowS3LogDelivery"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# ===========================================================================
# Access-log bucket — receives server access logs from the state bucket
# ===========================================================================

resource "aws_s3_bucket" "logs" {
  bucket        = local.log_bucket_name
  force_destroy = var.force_destroy

  # This IS the log destination, so it does not log to itself (that would
  # recurse), and cross-region replication / event notifications are out of
  # scope for an access-log sink.
  #checkov:skip=CKV_AWS_18:This is the log-target bucket; self-logging would recurse.
  #checkov:skip=CKV_AWS_144:Single-region reference; replication is out of scope for a log sink.
  #checkov:skip=CKV2_AWS_62:No event-notification consumer for access logs.
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
      kms_master_key_id = aws_kms_key.state.arn
    }
    # Bucket keys cut KMS request costs and are required for SSE-KMS log delivery.
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
    # Disable ACLs entirely; access is granted by bucket policy only.
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "logs" {
  # Deny anything not using TLS.
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

  # Allow S3 access-log delivery to write into this bucket, scoped to the state
  # bucket as the source and this account as the owner.
  statement {
    sid       = "AllowS3LogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:s3:::${local.state_bucket_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

# ===========================================================================
# State bucket — versioned, KMS-encrypted, TLS-only, access-logged
# ===========================================================================

resource "aws_s3_bucket" "state" {
  bucket        = local.state_bucket_name
  force_destroy = var.force_destroy

  # Versioning + lifecycle give point-in-time state recovery in one region;
  # cross-region replication and event notifications are deliberately out of
  # scope for this reference. See docs/decisions.
  #checkov:skip=CKV_AWS_144:Single-region reference; versioning+lifecycle cover recovery.
  #checkov:skip=CKV2_AWS_62:No event-notification consumer for the state bucket.
  tags = { Name = local.state_bucket_name }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.state.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "state-access/"
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

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
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# ===========================================================================
# DynamoDB — state lock table
# ===========================================================================

resource "aws_dynamodb_table" "lock" {
  name                        = local.lock_table_name
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "LockID"
  deletion_protection_enabled = var.deletion_protection

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  tags = { Name = local.lock_table_name }
}
