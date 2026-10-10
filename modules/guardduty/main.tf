# Account-level, one detector per account per Region. Only the
# account-baseline root module may call this module.

resource "aws_guardduty_detector" "this" {
  enable                       = true
  finding_publishing_frequency = var.finding_publishing_frequency
  tags                         = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_guardduty_detector_feature" "this" {
  for_each = toset(var.features)

  detector_id = aws_guardduty_detector.this.id
  name        = each.value
  status      = "ENABLED"
}
