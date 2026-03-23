variable "env_accounts" {
  description = "Map of environment name to workload account ID (e.g., dev => 123456789012)."
  type        = map(string)
}

variable "management_account_id" {
  description = "Management account ID where backend access roles are created."
  type        = string
}

variable "state_bucket_arn" {
  description = "ARN of centralized Terraform state bucket in management account."
  type        = string
}

variable "lock_table_arn" {
  description = "ARN of centralized DynamoDB lock table in management account."
  type        = string
}
