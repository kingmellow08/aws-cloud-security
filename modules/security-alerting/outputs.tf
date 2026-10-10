output "topic_arn" {
  description = "Security alerts SNS topic ARN."
  value       = aws_sns_topic.this.arn
}

output "topic_name" {
  description = "Security alerts SNS topic name."
  value       = aws_sns_topic.this.name
}

output "event_rule_names" {
  description = "EventBridge rule names keyed by purpose."
  value       = { for k, r in aws_cloudwatch_event_rule.this : k => r.name }
}
