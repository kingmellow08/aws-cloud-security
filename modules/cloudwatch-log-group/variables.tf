variable "name" {
  description = "Log group name."
  type        = string
}

variable "retention_in_days" {
  description = "Log retention period."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_in_days)
    error_message = "retention_in_days must be a value supported by CloudWatch Logs."
  }
}

variable "kms_key_arn" {
  description = "KMS key used to encrypt the log group. The key policy must allow logs.<region>.amazonaws.com."
  type        = string
}

variable "skip_destroy" {
  description = "Keep the log group in AWS when it is destroyed from state."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the log group."
  type        = map(string)
  default     = {}
}
