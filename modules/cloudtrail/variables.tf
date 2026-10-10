variable "name" {
  description = "Trail name."
  type        = string
}

variable "s3_bucket_name" {
  description = "Bucket receiving log files. Its policy must allow cloudtrail.amazonaws.com for this trail."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key encrypting log files."
  type        = string
}

variable "cloudwatch_log_group_arn" {
  description = "CloudWatch Logs log group ARN (without `:*`) receiving trail events."
  type        = string
}

variable "cloudwatch_logs_role_arn" {
  description = "Role CloudTrail assumes to write to CloudWatch Logs."
  type        = string
}

variable "s3_data_event_bucket_arns" {
  description = "Bucket ARNs whose object-level API activity is recorded."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the trail."
  type        = map(string)
  default     = {}
}
