variable "bucket_name" {
  description = "Exact S3 bucket name for Terraform state" 
  type        = string
}

variable "allowed_principal_arn_patterns" {
  description = "IAM principal ARN patterns allowed to access the Terraform state bucket"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags specific to this bucket"
  type        = map(string)
  default     = {}
}
