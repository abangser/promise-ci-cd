module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket = var.bucket_name

  versioning = {
    enabled = var.versioning_enabled
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "kratix"
  }
}
