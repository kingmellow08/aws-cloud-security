variable "name" {
  description = "Role name."
  type        = string
}

variable "path" {
  description = "IAM path. Paths scope deployer permissions (e.g. /acs/dev/), so keep them per owner."
  type        = string

  validation {
    condition     = can(regex("^/.+/$", var.path))
    error_message = "path must start and end with '/'."
  }
}

variable "description" {
  description = "Role description."
  type        = string
  default     = null
}

variable "trusted_service_principals" {
  description = "AWS service principals allowed to assume the role."
  type        = list(string)
}

variable "restrict_to_source_account" {
  description = "Add an aws:SourceAccount condition to the trust policy (confused-deputy protection). Not every service supplies this key."
  type        = bool
  default     = false
}

variable "managed_policy_arns" {
  description = "Managed policy ARNs attached to the role."
  type        = list(string)
  default     = []
}

variable "inline_policies" {
  description = "Map of inline policy name to policy JSON."
  type        = map(string)
  default     = {}
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary."
  type        = string
  default     = null
}

variable "create_instance_profile" {
  description = "Also create an EC2 instance profile with the same name."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the role."
  type        = map(string)
  default     = {}
}
