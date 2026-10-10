variable "finding_publishing_frequency" {
  description = "How often updated findings are exported to EventBridge."
  type        = string
  default     = "FIFTEEN_MINUTES"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.finding_publishing_frequency)
    error_message = "finding_publishing_frequency must be FIFTEEN_MINUTES, ONE_HOUR or SIX_HOURS."
  }
}

variable "features" {
  description = "GuardDuty protection plans to enable."
  type        = list(string)
  default     = ["S3_DATA_EVENTS", "EBS_MALWARE_PROTECTION", "RDS_LOGIN_EVENTS"]
}

variable "tags" {
  description = "Tags applied to the detector."
  type        = map(string)
  default     = {}
}
