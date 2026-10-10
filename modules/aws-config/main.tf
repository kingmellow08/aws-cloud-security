# AWS Config allows exactly one configuration recorder and one delivery
# channel per account per Region. Only the account-baseline root module may
# call this module; a second caller would fight over the same recorder.

resource "aws_config_configuration_recorder" "this" {
  name     = var.name
  role_arn = var.role_arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = var.include_global_resource_types
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = var.name
  s3_bucket_name = var.s3_bucket_name
  s3_key_prefix  = var.s3_key_prefix
  s3_kms_key_arn = var.s3_kms_key_arn

  snapshot_delivery_properties {
    delivery_frequency = var.snapshot_delivery_frequency
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

resource "aws_config_config_rule" "managed" {
  for_each = var.managed_rules

  name             = each.key
  input_parameters = each.value.input_parameters == null ? null : jsonencode(each.value.input_parameters)
  tags             = var.tags

  source {
    owner             = "AWS"
    source_identifier = each.value.source_identifier
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}
