variable "account_id" {
  description = "AWS account hosting this environment. The provider refuses any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "Region hosting this environment."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name. Must match the root module directory name."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "project_name" {
  description = "Project name; first segment of every state key."
  type        = string
  default     = "aws-cloud-security"
}

variable "name_prefix" {
  description = "Short prefix used in resource names. Must match bootstrap and account-baseline."
  type        = string
  default     = "acs"
}

variable "require_account_baseline" {
  description = "Fail the plan unless the account baseline (GuardDuty detector, alerts topic) already exists."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "VPC CIDR block. Must not overlap other environments that may be peered."
  type        = string
}

variable "azs" {
  description = "Availability zones."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs aligned with azs."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs aligned with azs."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway for private subnet egress."
  type        = bool
  default     = false
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the load balancer tier on 443."
  type        = list(string)
  default     = []
}

variable "app_port" {
  description = "Application port."
  type        = number
  default     = 8443
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "log_retention_days" {
  description = "Retention for environment CloudWatch log groups."
  type        = number
  default     = 90
}

variable "flow_log_max_aggregation_interval" {
  description = "VPC Flow Log aggregation interval (60 or 600 seconds)."
  type        = number
  default     = 600
}

variable "kms_deletion_window_days" {
  description = "Waiting period before the environment KMS key is deleted."
  type        = number
  default     = 30
}

variable "protect_from_destroy" {
  description = "Create the KMS key and data bucket with prevent_destroy and keep log groups on destroy."
  type        = bool
  default     = true
}

variable "force_destroy_buckets" {
  description = "Allow destroy to empty the data bucket. Ignored when protect_from_destroy = true."
  type        = bool
  default     = false
}

variable "rejected_flows_alarm_threshold" {
  description = "Rejected flow records per 5 minutes that raise a security alert."
  type        = number
  default     = 500
}
