output "environment" {
  description = "Environment this state owns."
  value       = var.environment
}

output "vpc_id" {
  description = "Environment VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnets keyed by AZ."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnets keyed by AZ."
  value       = module.vpc.private_subnet_ids
}

output "security_group_ids" {
  description = "Tiered security groups."
  value = {
    alb = module.security_groups.alb_security_group_id
    app = module.security_groups.app_security_group_id
    db  = module.security_groups.db_security_group_id
  }
}

output "kms_key_arn" {
  description = "Environment KMS key."
  value       = module.kms.key_arn
}

output "data_bucket" {
  description = "Environment data bucket."
  value       = module.data_bucket.bucket_id
}

output "log_groups" {
  description = "Environment log groups."
  value = {
    vpc_flow_logs = module.flow_logs_log_group.name
    application   = module.application_log_group.name
  }
}

output "iam_roles" {
  description = "Environment IAM roles."
  value = {
    vpc_flow_logs = module.flow_logs_role.role_arn
    app           = module.app_instance_role.role_arn
  }
}

output "app_instance_profile" {
  description = "Instance profile for application instances."
  value       = module.app_instance_role.instance_profile_name
}

output "security_alerts_topic_arn" {
  description = "Shared alerts topic (owned by account-baseline) used by this environment's alarms."
  value       = one(data.aws_sns_topic.security_alerts[*].arn)
}
