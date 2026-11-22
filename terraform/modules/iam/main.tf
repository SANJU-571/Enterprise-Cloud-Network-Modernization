###############################################################################
# IAM module
# Role-based groups from the IAM user summary:
#
#   Group               Access                 MFA   Region restriction
#   ComplianceAuditor   Console, read-only     Yes   Canada regions only
#   DevOps              Console + programmatic Yes   Canada regions only
#   DataEngineer        Programmatic only      Yes   Canada regions only
#
# Every group gets two shared guardrails:
#   * EnforceMFA      - deny everything except MFA self-service until the
#                       session is MFA-authenticated
#   * CanadaRegionOnly - deny actions outside ca-central-1 / ca-west-1
#                       (PIPEDA data residency), global services excepted
###############################################################################

locals {
  common_tags = merge(var.tags, { Module = "iam" })
}

resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}

# ---------------------------------------------------------------------------
# Shared guardrail policies
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "enforce_mfa" {
  statement {
    sid    = "AllowSelfServiceMFA"
    effect = "Allow"
    actions = [
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
      "iam:GetUser",
      "iam:ChangePassword",
    ]
    resources = [
      "arn:aws:iam::*:user/$${aws:username}",
      "arn:aws:iam::*:mfa/$${aws:username}",
    ]
  }

  statement {
    sid    = "DenyAllWithoutMFA"
    effect = "Deny"
    not_actions = [
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
      "iam:GetUser",
      "iam:ChangePassword",
      "sts:GetSessionToken",
    ]
    resources = ["*"]
    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "enforce_mfa" {
  name        = "${var.name}-EnforceMFA"
  description = "Deny all actions until the user authenticates with MFA"
  policy      = data.aws_iam_policy_document.enforce_mfa.json
  tags        = local.common_tags
}

data "aws_iam_policy_document" "region_restrict" {
  statement {
    sid    = "DenyOutsideCanada"
    effect = "Deny"
    not_actions = [
      "iam:*",
      "sts:*",
      "organizations:*",
      "support:*",
      "budgets:*",
      "ce:*",
      "cloudfront:*",
      "route53:*",
      "waf:*",
      "health:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }
}

resource "aws_iam_policy" "region_restrict" {
  name        = "${var.name}-CanadaRegionOnly"
  description = "Restrict regional API calls to Canadian regions (data residency)"
  policy      = data.aws_iam_policy_document.region_restrict.json
  tags        = local.common_tags
}

# ---------------------------------------------------------------------------
# ComplianceAuditor - read-only + security audit
# ---------------------------------------------------------------------------
resource "aws_iam_group" "auditor" {
  name = "ComplianceAuditor"
}

resource "aws_iam_group_policy_attachment" "auditor_readonly" {
  group      = aws_iam_group.auditor.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_group_policy_attachment" "auditor_security_audit" {
  group      = aws_iam_group.auditor.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

# ---------------------------------------------------------------------------
# DevOps - manage EC2, S3, ELB, ASG, CloudWatch; limited IAM (pass role only)
# ---------------------------------------------------------------------------
resource "aws_iam_group" "devops" {
  name = "DevOps"
}

data "aws_iam_policy_document" "devops" {
  statement {
    sid    = "InfraManagement"
    effect = "Allow"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "cloudwatch:*",
      "logs:*",
      "s3:*",
      "ssm:*",
      "rds:Describe*",
      "rds:RebootDBInstance",
      "rds:CreateDBSnapshot",
      "elasticache:Describe*",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassOnlyProjectRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole", "iam:GetRole", "iam:ListRoles"]
    resources = ["arn:aws:iam::*:role/${var.name}-*"]
  }

  statement {
    sid    = "DenyDestructiveDataOps"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketObjectLockConfiguration",
      "rds:DeleteDBInstance",
      "kms:ScheduleKeyDeletion",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "devops" {
  name   = "${var.name}-DevOps"
  policy = data.aws_iam_policy_document.devops.json
  tags   = local.common_tags
}

resource "aws_iam_group_policy_attachment" "devops" {
  group      = aws_iam_group.devops.name
  policy_arn = aws_iam_policy.devops.arn
}

# ---------------------------------------------------------------------------
# DataEngineer - programmatic read/process of client data in S3 + RDS IAM auth
# ---------------------------------------------------------------------------
resource "aws_iam_group" "data_engineer" {
  name = "DataEngineer"
}

data "aws_iam_policy_document" "data_engineer" {
  statement {
    sid       = "ReadClientData"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.data_bucket_arn, "${var.data_bucket_arn}/*"]
  }

  statement {
    sid       = "DecryptClientData"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }

  statement {
    sid       = "RdsIamAuth"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:*:*:dbuser:*/data_engineer"]
  }

  # Programmatic only - no console
  statement {
    sid       = "DenyConsole"
    effect    = "Deny"
    actions   = ["iam:CreateLoginProfile", "iam:UpdateLoginProfile"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "data_engineer" {
  name   = "${var.name}-DataEngineer"
  policy = data.aws_iam_policy_document.data_engineer.json
  tags   = local.common_tags
}

resource "aws_iam_group_policy_attachment" "data_engineer" {
  group      = aws_iam_group.data_engineer.name
  policy_arn = aws_iam_policy.data_engineer.arn
}

# ---------------------------------------------------------------------------
# Attach guardrails to every group
# ---------------------------------------------------------------------------
locals {
  groups = {
    auditor       = aws_iam_group.auditor.name
    devops        = aws_iam_group.devops.name
    data_engineer = aws_iam_group.data_engineer.name
  }
}

resource "aws_iam_group_policy_attachment" "mfa" {
  for_each   = local.groups
  group      = each.value
  policy_arn = aws_iam_policy.enforce_mfa.arn
}

resource "aws_iam_group_policy_attachment" "region" {
  for_each   = local.groups
  group      = each.value
  policy_arn = aws_iam_policy.region_restrict.arn
}

# ---------------------------------------------------------------------------
# CloudTrail - multi-region, log file validation, KMS encrypted
# ---------------------------------------------------------------------------
resource "aws_cloudtrail" "this" {
  count                         = var.cloudtrail_bucket == "" ? 0 : 1
  name                          = "${var.name}-trail"
  s3_bucket_name                = var.cloudtrail_bucket
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = var.kms_key_arn

  tags = local.common_tags
}
