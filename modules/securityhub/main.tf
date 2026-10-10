# AWS Security Hub CSPM (the Terraform resources keep the `securityhub`
# name). Account-level, one hub per account per Region. Only the
# account-baseline root module may call this module.

data "aws_partition" "current" {}
data "aws_region" "current" {}

resource "aws_securityhub_account" "this" {
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_securityhub_standards_subscription" "this" {
  for_each = toset(var.standards)

  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.region}::standards/${each.value}"

  depends_on = [aws_securityhub_account.this]
}
