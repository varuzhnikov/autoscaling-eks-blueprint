variable "table_name" {
  type        = string
  description = "DynamoDB table name for Terraform state locking" 
}

variable "allowed_principal_arn_patterns" {
  description = "IAM principal ARN patterns allowed to access the DynamoDB lock table"
  type        = list(string)
  default     = []
}


variable "tags" {
  type    = map(string)
  default = {}
}
