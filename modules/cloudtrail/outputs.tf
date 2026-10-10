output "trail_arn" {
  description = "Trail ARN."
  value       = aws_cloudtrail.this.arn
}

output "trail_name" {
  description = "Trail name."
  value       = aws_cloudtrail.this.name
}
