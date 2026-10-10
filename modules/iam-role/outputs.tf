output "role_name" {
  description = "Role name."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "Role ARN."
  value       = aws_iam_role.this.arn
}

output "instance_profile_name" {
  description = "Instance profile name, or null when not created."
  value       = one(aws_iam_instance_profile.this[*].name)
}
