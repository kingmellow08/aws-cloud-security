variable "name" {
  description = "SNS topic name; also prefixes EventBridge rule names."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for topic encryption. Must allow events.amazonaws.com and cloudwatch.amazonaws.com."
  type        = string
}

variable "email_addresses" {
  description = "Email endpoints subscribed to the topic. Each must confirm the subscription."
  type        = list(string)
  default     = []
}

variable "guardduty_min_severity" {
  description = "Minimum GuardDuty severity (0-10) that triggers an alert."
  type        = number
  default     = 7
}

variable "securityhub_severity_labels" {
  description = "Security Hub CSPM severity labels that trigger an alert."
  type        = list(string)
  default     = ["HIGH", "CRITICAL"]
}

variable "tags" {
  description = "Tags applied to alerting resources."
  type        = map(string)
  default     = {}
}
