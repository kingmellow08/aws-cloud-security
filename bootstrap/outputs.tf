output "state_bucket_name" {
  description = "S3 bucket holding remote state for this account."
  value       = module.state_bucket.bucket_id
}

output "state_kms_key_arn" {
  description = "KMS key encrypting remote state."
  value       = module.state_kms.key_arn
}

output "backend_config_file" {
  description = "Partial backend configuration to pass to `terraform init -backend-config=...`."
  value       = abspath(local_file.backend_config.filename)
}

output "state_keys" {
  description = "State key per root module."
  value       = local.state_keys
}

output "deployer_role_arns" {
  description = "Authorised deployment role per root module."
  value       = { for s, r in aws_iam_role.deployer : s => r.arn }
}

output "workload_boundary_policy_arns" {
  description = "Permissions boundary per environment."
  value       = { for e, p in aws_iam_policy.workload_boundary : e => p.arn }
}
