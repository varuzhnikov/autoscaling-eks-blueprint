variable "bucket_name" {
  description = "Exact S3 bucket name for Terraform state" 
  type        = string
}

variable "allowed_role" {
  description = "IAM role allowed to access the Terraform state bucket"
  type        = string
}

variable "tags" {
  description = "Additional tags specific to this bucket"
  type        = map(string)
  default     = {}
}
