output "key_arn" {
  description = "ARN of the KMS key."
  value       = local.key.arn
}

output "key_id" {
  description = "ID of the KMS key."
  value       = local.key.key_id
}

output "alias_arn" {
  description = "ARN of the KMS alias."
  value       = aws_kms_alias.this.arn
}
