variable "name" {
  description = "Name prefix for the security groups."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to."
  type        = string
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the load balancer on 443. Empty means no inbound access."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.alb_ingress_cidrs, "0.0.0.0/0") || length(var.alb_ingress_cidrs) == 1
    error_message = "If 0.0.0.0/0 is used it must be the only entry, to make the exposure explicit."
  }
}

variable "app_port" {
  description = "Application listener port."
  type        = number
  default     = 8443
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "tags" {
  description = "Tags applied to all security groups."
  type        = map(string)
  default     = {}
}
