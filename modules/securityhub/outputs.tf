output "hub_arn" {
  description = "Security Hub CSPM hub ARN."
  value       = aws_securityhub_account.this.arn
}

output "standards_subscription_arns" {
  description = "Enabled standards subscriptions."
  value       = [for s in aws_securityhub_standards_subscription.this : s.id]
}
