# Non-secret account-baseline settings. Set the target account explicitly:
#   export TF_VAR_account_id=<12-digit id>
aws_region   = "us-east-1"
project_name = "aws-cloud-security"
name_prefix  = "acs"

# Set to e.g. "us-west-2" to enable regional services there via the
# aws.secondary provider alias. Findings aggregate into aws_region.
secondary_region = null

# Each address receives a confirmation email from SNS.
alert_email_addresses = []

cloudtrail_log_retention_days = 365
log_archive_noncurrent_days   = 365
guardduty_min_alert_severity  = 7
