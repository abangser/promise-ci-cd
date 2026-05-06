variable "bucket_name" {
  description = "Globally unique name for the S3 bucket"
  type        = string
  default     = ""
}

variable "versioning_enabled" {
  description = "Enable S3 object versioning"
  type        = bool
  default     = false
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, production)"
  type        = string
  default     = "dev"
}
