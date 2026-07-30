# ---------------------------------------------------------------------------
# IAM baseline — least privilege by construction.
#
# Three roles, three ways of eliminating long-lived credentials:
#   1. GitHub Actions assumes a role via OIDC        → no AWS keys in CI
#   2. Humans assume a read-only auditor role via MFA → no standing access
#   3. EC2 uses SSM Session Manager                   → no SSH keys, no bastion
#
# Every policy is built from aws_iam_policy_document, never an inline JSON
# heredoc, so the plan output is diffable and the intent is typed.
# ---------------------------------------------------------------------------

data "aws_partition" "current" {}

# =====================================================================
# 1. GitHub Actions OIDC provider + role — the centrepiece
# =====================================================================

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.github_oidc_thumbprints

  tags = { Name = "${var.name_prefix}-github-oidc" }
}

# When the provider already exists (account-global, created by another
# environment) reference it instead of creating a duplicate.
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  attach_state_policy = var.state_bucket_arn != null
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    # Audience must be AWS STS — proves the token was minted for us.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # THE WHOLE POINT OF THIS MODULE.
    #
    # `sub` is pinned to one repo AND one branch:
    #   repo:<org>/<repo>:ref:refs/heads/<branch>
    #
    # A wildcard here is a full account takeover waiting to happen:
    #   repo:<org>/*        → every repo in the org can assume this role
    #   repo:*              → ANY repo on GitHub, owned by anyone, can assume it
    # An attacker just pushes a workflow to a repo matching the pattern and
    # inherits these AWS permissions. StringEquals on the exact sub — never
    # StringLike with a wildcard — is what keeps the trust boundary real.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${var.name_prefix}-github-actions"
  assume_role_policy   = data.aws_iam_policy_document.github_assume.json
  max_session_duration = 3600

  tags = { Name = "${var.name_prefix}-github-actions" }
}

# Least-privilege remote-state access — the only standing permission the CI role
# gets from this module. Scoped to the specific bucket, lock table, and key.
data "aws_iam_policy_document" "github_state" {
  count = local.attach_state_policy ? 1 : 0

  statement {
    sid       = "StateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]
  }

  statement {
    sid    = "StateObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${var.state_bucket_arn}/*"]
  }

  dynamic "statement" {
    for_each = var.state_lock_table_arn != null ? [1] : []
    content {
      sid    = "StateLockTable"
      effect = "Allow"
      actions = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
      ]
      resources = [var.state_lock_table_arn]
    }
  }

  dynamic "statement" {
    for_each = var.state_kms_key_arn != null ? [1] : []
    content {
      sid    = "StateKmsDecrypt"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
      ]
      resources = [var.state_kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "github_state" {
  count = local.attach_state_policy ? 1 : 0

  name   = "${var.name_prefix}-github-state"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_state[0].json
}

# =====================================================================
# 2. Read-only auditor role — assumable only with MFA
# =====================================================================

data "aws_iam_policy_document" "auditor_assume" {
  statement {
    sid     = "AssumeWithMFA"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.auditor_principal_arns
    }

    # No MFA, no audit session. Read-only is still read-of-everything, so we
    # refuse to hand it out on a bare long-lived credential.
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "auditor" {
  name                 = "${var.name_prefix}-auditor"
  assume_role_policy   = data.aws_iam_policy_document.auditor_assume.json
  max_session_duration = 3600

  tags = { Name = "${var.name_prefix}-auditor" }
}

# AWS-managed, curated read-only policies. SecurityAudit surfaces configuration;
# ViewOnlyAccess lets the auditor list and describe resources. Neither can mutate.
resource "aws_iam_role_policy_attachment" "auditor_security_audit" {
  role       = aws_iam_role.auditor.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/SecurityAudit"
}

resource "aws_iam_role_policy_attachment" "auditor_view_only" {
  role       = aws_iam_role.auditor.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/job-function/ViewOnlyAccess"
}

# =====================================================================
# 3. EC2 instance role — SSM only, no SSH
# =====================================================================

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    sid     = "EC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_instance" {
  name               = "${var.name_prefix}-ec2-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${var.name_prefix}-ec2-instance" }
}

# AmazonSSMManagedInstanceCore is the ONLY policy. It grants Session Manager,
# which replaces SSH entirely: no port 22, no key pairs, no bastion host, and
# every session is logged and IAM-authorised.
resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_instance" {
  name = "${var.name_prefix}-ec2-instance"
  role = aws_iam_role.ec2_instance.name

  tags = { Name = "${var.name_prefix}-ec2-instance" }
}
