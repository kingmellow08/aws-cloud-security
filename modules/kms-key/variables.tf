variable "alias" {
  description = "Alias name without the `alias/` prefix."
  type        = string
}

variable "description" {
  description = "Human-readable key description."
  type        = string
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion completes."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "additional_policy_json" {
  description = "Optional IAM policy JSON merged into the key policy (e.g. service principal grants)."
  type        = string
  default     = null
}

variable "prevent_destroy" {
  description = "When true the key is created with lifecycle.prevent_destroy."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the key."
  type        = map(string)
  default     = {}
}
