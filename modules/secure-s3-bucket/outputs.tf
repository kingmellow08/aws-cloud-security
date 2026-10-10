output "bucket_id" {
  description = "Name of the bucket."
  value       = local.bucket_name
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = one(concat(aws_s3_bucket.protected[*].arn, aws_s3_bucket.unprotected[*].arn))
}
