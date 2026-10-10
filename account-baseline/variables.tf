variable "account_id" {
  description = "AWS account this baseline belongs to. The provider refuses any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "Home Region for the account baseline."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Optional second Region in which to enable GuardDuty, Security Hub CSPM, Config and EBS default encryption. null disables it."
  type        = string
  default     = null
}

variable "project_name" {
  description = "Project name; first segment of every state key."
  type        = string
  default     = "aws-cloud-security"
}

variable "name_prefix" {
  description = "Short prefix used in resource names. Must match bootstrap and the environments."
  type        = string
  default     = "acs"
}

variable "state_bucket_name" {
  description = "Terraform state bucket whose object access is recorded by CloudTrail. null derives the bootstrap naming convention."
  type        = string
  default     = null
}

variable "alert_email_addresses" {
  description = "Email addresses subscribed to the shared security alerts topic."
  type        = list(string)
  default     = []
}

variable "cloudtrail_log_retention_days" {
  description = "CloudWatch Logs retention for the CloudTrail log group."
  type        = number
  default     = 365
}

variable "log_archive_noncurrent_days" {
  description = "Days to keep noncurrent versions of CloudTrail and Config objects."
  type        = number
  default     = 365
}

variable "guardduty_features" {
  description = "GuardDuty protection plans to enable."
  type        = list(string)
  default     = ["S3_DATA_EVENTS", "EBS_MALWARE_PROTECTION", "RDS_LOGIN_EVENTS"]
}

variable "guardduty_min_alert_severity" {
  description = "Minimum GuardDuty severity forwarded to the alerts topic."
  type        = number
  default     = 7
}

variable "securityhub_standards" {
  description = "Security Hub CSPM standards, as the path after `standards/` in the ARN."
  type        = list(string)
  default = [
    "aws-foundational-security-best-practices/v/1.0.0",
    "cis-aws-foundations-benchmark/v/3.0.0",
  ]
}

variable "config_managed_rules" {
  description = "AWS managed Config rules evaluated in the home Region, keyed by short name."
  type = map(object({
    source_identifier = string
    input_parameters  = optional(map(string))
  }))
  default = {
    cloudtrail-enabled                = { source_identifier = "CLOUD_TRAIL_ENABLED" }
    multi-region-cloudtrail-enabled   = { source_identifier = "MULTI_REGION_CLOUD_TRAIL_ENABLED" }
    guardduty-enabled-centralized     = { source_identifier = "GUARDDUTY_ENABLED_CENTRALIZED" }
    securityhub-enabled               = { source_identifier = "SECURITYHUB_ENABLED" }
    vpc-flow-logs-enabled             = { source_identifier = "VPC_FLOW_LOGS_ENABLED" }
    vpc-default-security-group-closed = { source_identifier = "VPC_DEFAULT_SECURITY_GROUP_CLOSED" }
    s3-bucket-ssl-requests-only       = { source_identifier = "S3_BUCKET_SSL_REQUESTS_ONLY" }
    s3-bucket-public-read-prohibited  = { source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED" }
    ec2-ebs-encryption-by-default     = { source_identifier = "EC2_EBS_ENCRYPTION_BY_DEFAULT" }
    cmk-backing-key-rotation-enabled  = { source_identifier = "CMK_BACKING_KEY_ROTATION_ENABLED" }
    cloudwatch-log-group-encrypted    = { source_identifier = "CLOUDWATCH_LOG_GROUP_ENCRYPTED" }
  }
}
