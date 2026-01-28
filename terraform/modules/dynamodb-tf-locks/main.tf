resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  # Lock identifier used by Terraform to manage exclusive access
  attribute {
    name = "LockID"
    type = "S"
  }


  deletion_protection_enabled = true


  tags = var.tags
}
