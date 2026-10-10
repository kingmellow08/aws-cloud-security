variable "bucket_name" {
  description = "Globally unique bucket name."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer managed KMS key used for default bucket encryption."
  type        = string
}

variable "prevent_destroy" {
  description = "When true the bucket is created with lifecycle.prevent_destroy and force_destroy is ignored."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow Terraform to delete a non-empty bucket. Only honoured when prevent_destroy = false."
  type        = bool
  default     = false
}

variable "noncurrent_version_expiration_days" {
  description = "Days to keep noncurrent object versions."
  type        = number
  default     = 90
}

variable "expiration_days" {
  description = "Optional expiry for current object versions. null keeps objects indefinitely."
  type        = number
  default     = null
}

variable "additional_policy_json" {
  description = "Optional bucket policy JSON merged with the module's transport/encryption guardrails."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the bucket."
  type        = map(string)
  default     = {}
}
