# Environment root module. This file is identical in dev, staging and prod;
# only backend.tf (state key) and terraform.tfvars differ. Every resource
# here is environment-scoped. Account-level security services are owned by
# account-baseline and are only *read* below, never declared.

data "aws_partition" "current" {}

locals {
  partition        = data.aws_partition.current.partition
  name             = "${var.name_prefix}-${var.environment}"
  iam_path         = "/${var.name_prefix}/${var.environment}/"
  log_group_prefix = "/${var.name_prefix}/${var.environment}"
}

# Guard against running one environment's tfvars in another's directory,
# which would point this state at the wrong environment's resources.
resource "terraform_data" "environment_guard" {
  input = var.environment

  lifecycle {
    precondition {
      condition     = var.environment == basename(abspath(path.root))
      error_message = "environment (${var.environment}) does not match the root module directory (${basename(abspath(path.root))})."
    }
  }
}

# ---------------------------------------------------------------------------
# Prerequisites owned by other states (read-only lookups)
# ---------------------------------------------------------------------------

# Created by bootstrap. Every IAM role below must carry it.
data "aws_iam_policy" "workload_boundary" {
  name        = "${local.name}-workload-boundary"
  path_prefix = "/${var.name_prefix}/terraform/"
}

# Created by account-baseline. Looking these up (instead of reading the
# baseline's state file) keeps the environment's deployer role away from
# baseline state while still failing fast if the baseline is missing.
data "aws_guardduty_detector" "baseline" {
  count = var.require_account_baseline ? 1 : 0
}

data "aws_sns_topic" "security_alerts" {
  count = var.require_account_baseline ? 1 : 0

  name = "${var.name_prefix}-baseline-security-alerts"
}

# ---------------------------------------------------------------------------
# Environment encryption key
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "kms" {
  statement {
    sid       = "CloudWatchLogsEnvironmentGroups"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.aws_region}:${var.account_id}:log-group:${local.log_group_prefix}/*"]
    }
  }
}

module "kms" {
  source = "../../modules/kms-key"

  alias                   = "${local.name}-workloads"
  description             = "Encrypts ${var.environment} logs and data"
  deletion_window_in_days = var.kms_deletion_window_days
  prevent_destroy         = var.protect_from_destroy
  additional_policy_json  = data.aws_iam_policy_document.kms.json
}

# ---------------------------------------------------------------------------
# CloudWatch log groups
# ---------------------------------------------------------------------------

module "flow_logs_log_group" {
  source = "../../modules/cloudwatch-log-group"

  name              = "${local.log_group_prefix}/vpc-flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_arn       = module.kms.key_arn
  skip_destroy      = var.protect_from_destroy
}

module "application_log_group" {
  source = "../../modules/cloudwatch-log-group"

  name              = "${local.log_group_prefix}/application"
  retention_in_days = var.log_retention_days
  kms_key_arn       = module.kms.key_arn
  skip_destroy      = var.protect_from_destroy
}

# ---------------------------------------------------------------------------
# Environment IAM roles
# ---------------------------------------------------------------------------

module "flow_logs_role" {
  source = "../../modules/iam-role"

  name                       = "${local.name}-vpc-flow-logs"
  path                       = local.iam_path
  description                = "VPC Flow Logs delivery for ${var.environment}"
  trusted_service_principals = ["vpc-flow-logs.amazonaws.com"]
  restrict_to_source_account = true
  permissions_boundary_arn   = data.aws_iam_policy.workload_boundary.arn

  inline_policies = {
    deliver-flow-logs = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid    = "DeliverFlowLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
        Resource = [
          module.flow_logs_log_group.arn,
          "${module.flow_logs_log_group.arn}:*",
        ]
      }]
    })
  }
}

module "app_instance_role" {
  source = "../../modules/iam-role"

  name                       = "${local.name}-app"
  path                       = local.iam_path
  description                = "Application instances in ${var.environment}"
  trusted_service_principals = ["ec2.amazonaws.com"]
  managed_policy_arns        = ["arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  permissions_boundary_arn   = data.aws_iam_policy.workload_boundary.arn
  create_instance_profile    = true

  inline_policies = {
    application-access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "DataBucketObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = "${module.data_bucket.bucket_arn}/*"
        },
        {
          Sid      = "DataBucketList"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = module.data_bucket.bucket_arn
        },
        {
          Sid      = "EnvironmentKey"
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
          Resource = module.kms.key_arn
        },
        {
          Sid      = "ApplicationLogs"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "${module.application_log_group.arn}:*"
        },
      ]
    })
  }
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  name                              = local.name
  cidr_block                        = var.vpc_cidr
  azs                               = var.azs
  public_subnet_cidrs               = var.public_subnet_cidrs
  private_subnet_cidrs              = var.private_subnet_cidrs
  enable_nat_gateway                = var.enable_nat_gateway
  flow_log_destination_arn          = module.flow_logs_log_group.arn
  flow_log_iam_role_arn             = module.flow_logs_role.role_arn
  flow_log_max_aggregation_interval = var.flow_log_max_aggregation_interval
}

module "security_groups" {
  source = "../../modules/security-groups"

  name              = local.name
  vpc_id            = module.vpc.vpc_id
  alb_ingress_cidrs = var.alb_ingress_cidrs
  app_port          = var.app_port
  db_port           = var.db_port
}

# ---------------------------------------------------------------------------
# Data storage
# ---------------------------------------------------------------------------

module "data_bucket" {
  source = "../../modules/secure-s3-bucket"

  bucket_name     = "${local.name}-data-${var.account_id}-${var.aws_region}"
  kms_key_arn     = module.kms.key_arn
  prevent_destroy = var.protect_from_destroy
  force_destroy   = var.force_destroy_buckets
}

# ---------------------------------------------------------------------------
# Environment detection feeding the shared alerts topic
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "rejected_flows" {
  name           = "${local.name}-rejected-flows"
  log_group_name = module.flow_logs_log_group.name
  pattern        = "[version, account_id, interface_id, srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, start, end, action=\"REJECT\", log_status]"

  metric_transformation {
    name      = "RejectedFlows"
    namespace = "${var.name_prefix}/${var.environment}/VPCFlowLogs"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "rejected_flows" {
  alarm_name          = "${local.name}-vpc-rejected-flows"
  alarm_description   = "Spike in rejected traffic in the ${var.environment} VPC (possible scanning)"
  namespace           = "${var.name_prefix}/${var.environment}/VPCFlowLogs"
  metric_name         = "RejectedFlows"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.rejected_flows_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = data.aws_sns_topic.security_alerts[*].arn
}
