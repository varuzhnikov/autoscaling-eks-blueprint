terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# DynamoDB table for Terraform state locking
# 
# This table stores lock entries to prevent concurrent Terraform operations
# from modifying the same state file simultaneously. Each lock entry uses
# the state file key (e.g., "dev/terraform.tfstate") as the LockID.
#
# Configuration:
# - PAY_PER_REQUEST billing: Low cost for lock operations (typically < 1 request/sec)
# - Single hash key (LockID): Simple key structure for lock entries
# - Deletion protection: Disabled by default (can be enabled for production)
# - Encryption: Enabled by default by AWS (server-side encryption at rest)
resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  # Lock identifier used by Terraform to manage exclusive access
  # Format: "<state-key-prefix>/terraform.tfstate" (e.g., "dev/terraform.tfstate")
  attribute {
    name = "LockID"
    type = "S"  # String type
  }

  # Prevent accidental table deletion
  deletion_protection_enabled = true

  # Server-side encryption is enabled by default by AWS
  # DynamoDB automatically encrypts all data at rest using AWS-managed keys
  # No explicit encryption configuration needed

  tags = var.tags
}

# DynamoDB resource policy for cross-account access
#
# Cross-account access is granted via a resource policy with ARN pattern conditions,
# so we avoid direct Principal references and IAM eventual consistency issues.
#
# Architecture:
# - This table policy is a coarse allowlist at the DynamoDB resource level
# - It admits multiple TerraformExecutionRole-* principals from different accounts
#   and SSO roles from Management account
# - Fine-grained scoping (per-environment lock keys) is enforced in each role's IAM policy
#   via dynamodb:LeadingKeys condition (e.g., dev/*, stage/*, prod/*)
# - This two-level approach:
#   1. Resource policy: "Who can access this table?" (coarse - all allowed roles)
#   2. IAM policy: "What keys can each role access?" (fine-grained - per environment)
#
# Why use Principal = "*" with condition instead of direct Principal references?
# - Avoids IAM eventual consistency issues (roles may not exist when policy is created)
# - Allows wildcard patterns for SSO roles (unpredictable names like aws-reserved/sso.amazonaws.com/*)
# - More flexible and maintainable
data "aws_iam_policy_document" "access" {
  count = length(var.allowed_principal_arn_patterns) > 0 ? 1 : 0

  statement {
    sid    = "AllowTerraformStateLocking"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem"
    ]

    resources = [aws_dynamodb_table.this.arn]

    # Why StringLike instead of StringEquals?
    # - allowed_principal_arn_patterns contains both exact ARNs and wildcard patterns:
    #   * Exact ARNs: "arn:aws:iam::<account-id>:role/TerraformExecutionRole-dev"
    #   * Wildcard patterns: "arn:aws:iam::<account-id>:role/aws-reserved/sso.amazonaws.com/*"
    # - StringEquals requires exact match (no wildcards supported)
    # - StringLike supports both exact matches AND wildcard patterns (*, ?)
    # - This allows SSO roles (unpredictable names require wildcards) while still
    #   supporting exact role ARNs (StringLike works for exact matches too)
    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = var.allowed_principal_arn_patterns
    }
  }
}

resource "aws_dynamodb_resource_policy" "this" {
  count       = length(var.allowed_principal_arn_patterns) > 0 ? 1 : 0
  resource_arn = aws_dynamodb_table.this.arn
  policy      = data.aws_iam_policy_document.access[0].json
}
