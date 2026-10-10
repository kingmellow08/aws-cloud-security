variable "standards" {
  description = "Standards to subscribe to, as the path after `standards/` in the standards ARN."
  type        = list(string)
  default = [
    "aws-foundational-security-best-practices/v/1.0.0",
    "cis-aws-foundations-benchmark/v/3.0.0",
  ]
}
