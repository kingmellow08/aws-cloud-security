output "security_alerts_topic_arn" {
  description = "Shared security alerts topic. Environments look it up by name rather than reading this state."
  value       = module.security_alerting.topic_arn
}

output "security_alerts_topic_name" {
  description = "Shared security alerts topic name."
  value       = module.security_alerting.topic_name
}

output "security_logs_kms_key_arn" {
  description = "KMS key protecting CloudTrail, Config and alerting data."
  value       = module.security_logs_kms.key_arn
}

output "cloudtrail_arn" {
  description = "Multi-Region trail ARN."
  value       = module.cloudtrail.trail_arn
}

output "cloudtrail_bucket" {
  description = "CloudTrail log archive bucket."
  value       = module.cloudtrail_bucket.bucket_id
}

output "config_bucket" {
  description = "AWS Config delivery bucket."
  value       = module.config_bucket.bucket_id
}

output "guardduty_detector_ids" {
  description = "GuardDuty detector per Region."
  value = merge(
    { (var.aws_region) = module.guardduty_home.detector_id },
    local.secondary_enabled ? { (var.secondary_region) = module.guardduty_secondary[0].detector_id } : {},
  )
}

output "securityhub_standards" {
  description = "Enabled Security Hub CSPM standards subscriptions in the home Region."
  value       = module.securityhub_home.standards_subscription_arns
}

output "config_rule_arns" {
  description = "Managed Config rules in the home Region."
  value       = module.config_home.config_rule_arns
}
