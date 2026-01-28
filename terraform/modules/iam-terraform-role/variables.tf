variable "role_name" {
  description = "Name of the Terraform execution IAM role"
  type        = string
}

variable "aws_region" {
  description = "AWS region where this role is allowed to operate"
  type        = string
}

variable "account_id" {
  description  = "AWS account ID"
  type        = string
}

variable "trusted_role_arns" {
  description = "SSO / CI roles allowed to assume this Terraform role" 
  type        = list(string)
}

variable "state_bucket_arn" {
  description = "ARN of the S3 bucket used for Terraform state"
  type        = string
}

variable "lock_table_arn" {
  description = "ARN of the DynamoDB table used for Terraform state locking"
  type        = string
}
