output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = module.s3_bucket.s3_bucket_id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = module.s3_bucket.s3_bucket_arn
}
