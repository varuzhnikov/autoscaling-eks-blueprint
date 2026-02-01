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

variable "trusted_principal_arn_patterns" {
  description = "IAM principal ARN patterns (SSO or CI) allowed to assume this Terraform execution role" 
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

variable "state_key_prefix" {
  description = "State key prefix (e.g., dev/, stage/, prod/, management/) used to scope backend access. Required for environment isolation."
  type        = string
  # No default - prefix is always required for security (environment isolation)
}

variable "permissions_mode" {
  description = "Permissions mode: 'broad' for Dev (PowerUserAccess-like), 'hardened' for Stage/Prod (minimal permissions)"
  type        = string
  default     = "hardened"
  validation {
    condition     = contains(["broad", "hardened", "custom"], var.permissions_mode)
    error_message = "permissions_mode must be 'broad', 'hardened', or 'custom'"
  }
}

variable "additional_permissions" {
  description = "Additional IAM policy statements (list of policy documents) for custom permissions mode"
  type        = list(object({
    sid       = optional(string)
    effect    = string
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []
}

variable "require_mfa" {
  description = "Require MFA for assume role (recommended for Stage/Prod)"
  type        = bool
  default     = false
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds (default: 3600 for hardened, 28800 for broad)"
  type        = number
  default     = null
  validation {
    condition     = var.max_session_duration == null || (var.max_session_duration >= 3600 && var.max_session_duration <= 43200)
    error_message = "max_session_duration must be between 3600 (1 hour) and 43200 (12 hours) - AWS minimum requirement"
  }
}
