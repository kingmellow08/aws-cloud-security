output "alb_security_group_id" {
  description = "Load balancer tier security group."
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "Application tier security group."
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "Database tier security group."
  value       = aws_security_group.db.id
}
