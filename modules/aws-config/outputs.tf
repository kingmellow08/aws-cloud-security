output "recorder_name" {
  description = "Configuration recorder name."
  value       = aws_config_configuration_recorder.this.name
}

output "config_rule_arns" {
  description = "Managed Config rule ARNs keyed by rule name."
  value       = { for k, r in aws_config_config_rule.managed : k => r.arn }
}
