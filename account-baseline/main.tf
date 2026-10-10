# Account-level security baseline. Every resource here exists once per AWS
# account (or once per account per Region) and must not be declared in any
# environment root module. Environments consume the alerting topic by name.

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition
  name      = "${var.name_prefix}-baseline"
  iam_path  = "/${var.name_prefix}/baseline/"

  secondary_enabled = var.secondary_region != null && var.secondary_region != var.aws_region

  trail_name = "${local.name}-trail"
  trail_arn  = "arn:${local.partition}:cloudtrail:${var.aws_region}:${var.account_id}:trail/${local.trail_name}"

  cloudtrail_bucket_name    = "${local.name}-cloudtrail-${var.account_id}-${var.aws_region}"
  cloudtrail_bucket_arn     = "arn:${local.partition}:s3:::${local.cloudtrail_bucket_name}"
  config_bucket_name        = "${local.name}-config-${var.account_id}-${var.aws_region}"
  config_bucket_arn         = "arn:${local.partition}:s3:::${local.config_bucket_name}"
  cloudtrail_log_group_name = "/${var.name_prefix}/baseline/cloudtrail"

  state_bucket_name = coalesce(var.state_bucket_name, "${var.name_prefix}-tfstate-${var.account_id}-${var.aws_region}")
}

# ---------------------------------------------------------------------------
# Encryption for security logs and alerts
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "security_logs_kms" {
  statement {
    sid       = "CloudTrailEncryptLogs"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:${local.partition}:cloudtrail:*:${var.account_id}:trail/*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "CloudTrailDescribeKey"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "ConfigDelivery"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }

  statement {
    sid       = "CloudWatchLogsBaselineGroups"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.aws_region}:${var.account_id}:log-group:/${var.name_prefix}/baseline/*"]
    }
  }

  statement {
    sid       = "AlertPublishers"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
  }
}

module "security_logs_kms" {
  source = "../modules/kms-key"

  alias                   = "${local.name}-security-logs"
  description             = "Encrypts CloudTrail, Config and security alerting data for account ${var.account_id}"
  deletion_window_in_days = 30
  prevent_destroy         = true
  additional_policy_json  = data.aws_iam_policy_document.security_logs_kms.json
}

# ---------------------------------------------------------------------------
# Log archive buckets
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [local.cloudtrail_bucket_arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${local.cloudtrail_bucket_arn}/AWSLogs/${var.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

module "cloudtrail_bucket" {
  source = "../modules/secure-s3-bucket"

  bucket_name                        = local.cloudtrail_bucket_name
  kms_key_arn                        = module.security_logs_kms.key_arn
  prevent_destroy                    = true
  noncurrent_version_expiration_days = var.log_archive_noncurrent_days
  additional_policy_json             = data.aws_iam_policy_document.cloudtrail_bucket.json
}

data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid       = "AWSConfigBucketPermissionsCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [local.config_bucket_arn]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }

  statement {
    sid       = "AWSConfigBucketDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${local.config_bucket_arn}/AWSLogs/${var.account_id}/Config/*"]

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
      values   = [var.account_id]
    }
  }
}

module "config_bucket" {
  source = "../modules/secure-s3-bucket"

  bucket_name                        = local.config_bucket_name
  kms_key_arn                        = module.security_logs_kms.key_arn
  prevent_destroy                    = true
  noncurrent_version_expiration_days = var.log_archive_noncurrent_days
  additional_policy_json             = data.aws_iam_policy_document.config_bucket.json
}

# ---------------------------------------------------------------------------
# CloudTrail (multi-Region, account level)
# ---------------------------------------------------------------------------

module "cloudtrail_log_group" {
  source = "../modules/cloudwatch-log-group"

  name              = local.cloudtrail_log_group_name
  retention_in_days = var.cloudtrail_log_retention_days
  kms_key_arn       = module.security_logs_kms.key_arn
  skip_destroy      = true
}

module "cloudtrail_logs_role" {
  source = "../modules/iam-role"

  name                       = "${local.name}-cloudtrail-to-cwl"
  path                       = local.iam_path
  description                = "CloudTrail delivery to ${local.cloudtrail_log_group_name}"
  trusted_service_principals = ["cloudtrail.amazonaws.com"]

  inline_policies = {
    deliver-to-cloudwatch-logs = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "DeliverTrailEvents"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${module.cloudtrail_log_group.arn}:log-stream:*"
      }]
    })
  }
}

module "cloudtrail" {
  source = "../modules/cloudtrail"

  name                      = local.trail_name
  s3_bucket_name            = module.cloudtrail_bucket.bucket_id
  kms_key_arn               = module.security_logs_kms.key_arn
  cloudwatch_log_group_arn  = module.cloudtrail_log_group.arn
  cloudwatch_logs_role_arn  = module.cloudtrail_logs_role.role_arn
  s3_data_event_bucket_arns = ["arn:${local.partition}:s3:::${local.state_bucket_name}"]

  # The bucket policy must exist before CloudTrail validates delivery.
  depends_on = [module.cloudtrail_bucket]
}

# ---------------------------------------------------------------------------
# AWS Config
# ---------------------------------------------------------------------------

module "config_role" {
  source = "../modules/iam-role"

  name                       = "${local.name}-config"
  path                       = local.iam_path
  description                = "AWS Config recorder for account ${var.account_id}"
  trusted_service_principals = ["config.amazonaws.com"]
  restrict_to_source_account = true
  managed_policy_arns        = ["arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"]

  inline_policies = {
    deliver-to-config-bucket = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "WriteConfigHistory"
          Effect   = "Allow"
          Action   = ["s3:PutObject"]
          Resource = "${local.config_bucket_arn}/AWSLogs/${var.account_id}/Config/*"
          Condition = {
            StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
          }
        },
        {
          Sid      = "CheckConfigBucket"
          Effect   = "Allow"
          Action   = ["s3:GetBucketAcl"]
          Resource = local.config_bucket_arn
        },
        {
          Sid      = "EncryptConfigHistory"
          Effect   = "Allow"
          Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
          Resource = module.security_logs_kms.key_arn
        },
      ]
    })
  }
}

module "config_home" {
  source = "../modules/aws-config"

  name                          = local.name
  role_arn                      = module.config_role.role_arn
  s3_bucket_name                = module.config_bucket.bucket_id
  s3_kms_key_arn                = module.security_logs_kms.key_arn
  include_global_resource_types = true
  managed_rules                 = { for k, v in var.config_managed_rules : "${local.name}-${k}" => v }
}

module "config_secondary" {
  source = "../modules/aws-config"
  count  = local.secondary_enabled ? 1 : 0

  providers = {
    aws = aws.secondary
  }

  name                          = local.name
  role_arn                      = module.config_role.role_arn
  s3_bucket_name                = module.config_bucket.bucket_id
  s3_kms_key_arn                = module.security_logs_kms.key_arn
  include_global_resource_types = false
}

# ---------------------------------------------------------------------------
# GuardDuty
# ---------------------------------------------------------------------------

module "guardduty_home" {
  source = "../modules/guardduty"

  features = var.guardduty_features
}

module "guardduty_secondary" {
  source = "../modules/guardduty"
  count  = local.secondary_enabled ? 1 : 0

  providers = {
    aws = aws.secondary
  }

  features = var.guardduty_features
}

# ---------------------------------------------------------------------------
# AWS Security Hub CSPM
# ---------------------------------------------------------------------------

module "securityhub_home" {
  source = "../modules/securityhub"

  standards = var.securityhub_standards
}

module "securityhub_secondary" {
  source = "../modules/securityhub"
  count  = local.secondary_enabled ? 1 : 0

  providers = {
    aws = aws.secondary
  }

  standards = var.securityhub_standards
}

# Pull secondary-Region findings into the home Region so the single set of
# alerting rules below sees everything.
resource "aws_securityhub_finding_aggregator" "this" {
  count = local.secondary_enabled ? 1 : 0

  linking_mode      = "SPECIFIED_REGIONS"
  specified_regions = [var.secondary_region]

  depends_on = [module.securityhub_home, module.securityhub_secondary]
}

# ---------------------------------------------------------------------------
# Shared security alerting
# ---------------------------------------------------------------------------

module "security_alerting" {
  source = "../modules/security-alerting"

  name                   = "${local.name}-security-alerts"
  kms_key_arn            = module.security_logs_kms.key_arn
  email_addresses        = var.alert_email_addresses
  guardduty_min_severity = var.guardduty_min_alert_severity
}

# ---------------------------------------------------------------------------
# Account-wide guardrails
# ---------------------------------------------------------------------------

resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ebs_encryption_by_default" "home" {
  enabled = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ebs_encryption_by_default" "secondary" {
  count    = local.secondary_enabled ? 1 : 0
  provider = aws.secondary

  enabled = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "${local.name}-account-analyzer"
  type          = "ACCOUNT"
}
