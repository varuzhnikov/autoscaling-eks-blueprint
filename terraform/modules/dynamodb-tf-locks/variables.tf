variable "table_name" {
  type        = string
  description = "DynamoDB table name for Terraform state locking" 
}


variable "tags" {
  type    = map(string)
  default = {}
}
