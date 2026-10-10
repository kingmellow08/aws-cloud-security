# Multi-Region, account-level trail. Only the account-baseline root module
# may call this module.

resource "aws_cloudtrail" "this" {
  name                          = var.name
  s3_bucket_name                = var.s3_bucket_name
  kms_key_id                    = var.kms_key_arn
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${var.cloudwatch_log_group_arn}:*"
  cloud_watch_logs_role_arn     = var.cloudwatch_logs_role_arn
  tags                          = var.tags

  advanced_event_selector {
    name = "All management events"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  # Object-level auditing of sensitive buckets such as the Terraform state
  # bucket: every read or write of a state file is recorded.
  dynamic "advanced_event_selector" {
    for_each = length(var.s3_data_event_bucket_arns) > 0 ? [1] : []
    content {
      name = "S3 data events for audited buckets"

      field_selector {
        field  = "eventCategory"
        equals = ["Data"]
      }

      field_selector {
        field  = "resources.type"
        equals = ["AWS::S3::Object"]
      }

      field_selector {
        field       = "resources.ARN"
        starts_with = [for arn in var.s3_data_event_bucket_arns : "${arn}/"]
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
