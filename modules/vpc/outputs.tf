output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs keyed by AZ."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnet_ids" {
  description = "Private subnet IDs keyed by AZ."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "private_route_table_ids" {
  description = "Private route table IDs keyed by AZ."
  value       = { for az, rt in aws_route_table.private : az => rt.id }
}

output "flow_log_id" {
  description = "VPC Flow Log ID."
  value       = aws_flow_log.this.id
}
