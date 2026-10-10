variable "name" {
  description = "Name prefix for VPC resources."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR block."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR."
  }
}

variable "azs" {
  description = "Availability zones, one per subnet pair."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, aligned by index with azs. May be empty."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.public_subnet_cidrs) == 0 || length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs must be empty or have one entry per AZ."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, aligned by index with azs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs must have one entry per AZ."
  }
}

variable "enable_nat_gateway" {
  description = "Create a single NAT gateway for private subnet egress. Requires public subnets."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_nat_gateway || length(var.public_subnet_cidrs) > 0
    error_message = "enable_nat_gateway requires public_subnet_cidrs."
  }
}

variable "flow_log_destination_arn" {
  description = "CloudWatch Logs log group ARN receiving VPC Flow Logs."
  type        = string
}

variable "flow_log_iam_role_arn" {
  description = "IAM role VPC Flow Logs assumes to publish to CloudWatch Logs."
  type        = string
}

variable "flow_log_traffic_type" {
  description = "ACCEPT, REJECT or ALL."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "flow_log_max_aggregation_interval" {
  description = "Flow log aggregation interval in seconds (60 or 600)."
  type        = number
  default     = 600

  validation {
    condition     = contains([60, 600], var.flow_log_max_aggregation_interval)
    error_message = "flow_log_max_aggregation_interval must be 60 or 600."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
