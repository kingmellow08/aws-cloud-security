# Shared security alerting: one SNS topic per account that GuardDuty,
# Security Hub CSPM, tamper-detection rules and environment alarms publish to.
# Owned by account-baseline; environments only reference it by name.

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "this" {
  name              = var.name
  kms_master_key_id = var.kms_key_arn
  tags              = merge(var.tags, { Name = var.name })

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "topic" {
  statement {
    sid = "AccountOwnerManage"
    actions = [
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:AddPermission",
      "sns:RemovePermission",
      "sns:DeleteTopic",
      "sns:Subscribe",
      "sns:ListSubscriptionsByTopic",
      "sns:Publish",
    ]
    resources = [aws_sns_topic.this.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "AllowEventBridgeAndCloudWatchPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this.arn]

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

resource "aws_sns_topic_policy" "this" {
  arn    = aws_sns_topic.this.arn
  policy = data.aws_iam_policy_document.topic.json
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.email_addresses)

  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = each.value
}

locals {
  rules = {
    guardduty-findings = {
      description = "GuardDuty findings with severity >= ${var.guardduty_min_severity}"
      pattern = {
        source        = ["aws.guardduty"]
        "detail-type" = ["GuardDuty Finding"]
        detail        = { severity = [{ numeric = [">=", var.guardduty_min_severity] }] }
      }
    }

    securityhub-findings = {
      description = "New, active Security Hub CSPM findings at ${join("/", var.securityhub_severity_labels)} severity"
      pattern = {
        source        = ["aws.securityhub"]
        "detail-type" = ["Security Hub Findings - Imported"]
        detail = {
          findings = {
            Severity    = { Label = var.securityhub_severity_labels }
            Workflow    = { Status = ["NEW"] }
            RecordState = ["ACTIVE"]
          }
        }
      }
    }

    # Anyone disabling the account baseline outside Terraform raises an alert.
    security-tampering = {
      description = "API calls that disable or weaken account-level security services"
      pattern = {
        source        = ["aws.cloudtrail", "aws.guardduty", "aws.securityhub", "aws.config"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventName = [
            "StopLogging",
            "DeleteTrail",
            "UpdateTrail",
            "PutEventSelectors",
            "DeleteDetector",
            "UpdateDetector",
            "DisableSecurityHub",
            "BatchDisableStandards",
            "DeleteConfigurationRecorder",
            "StopConfigurationRecorder",
            "DeleteDeliveryChannel",
          ]
        }
      }
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rules

  name          = "${var.name}-${each.key}"
  description   = each.value.description
  event_pattern = jsonencode(each.value.pattern)
  tags          = var.tags
}

resource "aws_cloudwatch_event_target" "sns" {
  for_each = local.rules

  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = "security-alerts-sns"
  arn       = aws_sns_topic.this.arn
}
