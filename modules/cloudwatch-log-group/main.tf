resource "aws_cloudwatch_log_group" "this" {
  name              = var.name
  retention_in_days = var.retention_in_days
  kms_key_id        = var.kms_key_arn
  # skip_destroy leaves the log group (and its evidence) in place when the
  # owning state is destroyed; it is removed from state only.
  skip_destroy = var.skip_destroy
  tags         = merge(var.tags, { Name = var.name })
}
