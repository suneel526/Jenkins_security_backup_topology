variable "aws_region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "ap-south-2"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state"
  type        = string

  validation {
    condition     = length(var.state_bucket_name) >= 3 && length(var.state_bucket_name) <= 63
    error_message = "state_bucket_name must be a valid S3 bucket name between 3 and 63 characters."
  }
}
