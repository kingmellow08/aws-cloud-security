variable "name" {
  description = "Name of the configuration recorder and delivery channel."
  type        = string
}

variable "role_arn" {
  description = "IAM role AWS Config uses to read resource configuration and write to S3."
  type        = string
}

variable "s3_bucket_name" {
  description = "Bucket receiving configuration snapshots and history."
  type        = string
}

variable "s3_key_prefix" {
  description = "Optional key prefix inside the delivery bucket."
  type        = string
  default     = null
}

variable "s3_kms_key_arn" {
  description = "KMS key used to encrypt delivered objects."
  type        = string
}

variable "include_global_resource_types" {
  description = "Record IAM and other global resources. Enable in exactly one Region to avoid duplicates."
  type        = bool
  default     = true
}

variable "snapshot_delivery_frequency" {
  description = "Configuration snapshot delivery frequency."
  type        = string
  default     = "TwentyFour_Hours"
}

variable "managed_rules" {
  description = "AWS managed Config rules keyed by rule name."
  type = map(object({
    source_identifier = string
    input_parameters  = optional(map(string))
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to Config rules."
  type        = map(string)
  default     = {}
}
