variable "account_id" {
  description = "AWS account this bootstrap targets. The provider refuses to run against any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "Region of the state bucket."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "First segment of every state key: <project_name>/<scope>/terraform.tfstate."
  type        = string
  default     = "aws-cloud-security"
}

variable "name_prefix" {
  description = "Short prefix used in resource names. Must match name_prefix in every other root module."
  type        = string
  default     = "acs"
}

variable "state_scopes" {
  description = "Root modules that keep state in this account's bucket. Each gets its own key, deployer role and bucket-policy isolation."
  type        = list(string)
  default     = ["account-baseline", "dev", "staging", "prod"]

  validation {
    condition     = contains(var.state_scopes, "account-baseline")
    error_message = "Every account needs its own account-baseline scope."
  }

  validation {
    condition     = alltrue([for s in var.state_scopes : contains(["account-baseline", "dev", "staging", "prod"], s)])
    error_message = "state_scopes may only contain account-baseline, dev, staging and prod."
  }
}

variable "deployer_trusted_principal_arns" {
  description = "IAM principals (SSO permission-set roles, CI OIDC roles) allowed to assume the deployer roles. Empty trusts the account root, i.e. any IAM principal granted sts:AssumeRole."
  type        = list(string)
  default     = []
}

variable "require_mfa" {
  description = "Require MFA to assume deployer roles. Set false only when every trusted principal is a CI role."
  type        = bool
  default     = true
}

variable "break_glass_principal_arns" {
  description = "Principals exempt from per-scope state isolation and allowed to delete state versions. Keep empty or tightly controlled."
  type        = list(string)
  default     = []
}

variable "state_noncurrent_version_retention_days" {
  description = "Days to keep previous versions of every state file for recovery."
  type        = number
  default     = 365
}
