# ------------------------------------------------------------
# Terraform state S3 backend module
# ------------------------------------------------------------
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# This module creates a secure S3 bucket for storing Terraform remote state.
# The bucket is private by default and access is restricted to multiple IAM roles
# via ARN patterns (e.g., TerraformExecutionRole-* from different accounts,
# SSO roles from Management account). ACL-based access is disabled;
# IAM roles and bucket policy are used instead.

# Create S3 bucket for Terraform remote state
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
 
  # Prevents Terraform from deleting the bucket during a 'destroy' operation
  lifecycle {
    prevent_destroy = true
  }

  tags = var.tags
}

# Enforce bucket ownership and fully disable ACL usage.
# 
# What this does:
# - Sets object_ownership to "BucketOwnerEnforced" (AWS best practice since 2021)
# - Disables ACLs (Access Control Lists) completely - ACLs are ignored
# - All objects in the bucket are owned by the bucket owner (Management account)
# - Access control is handled EXCLUSIVELY via IAM policies and bucket policy
#
# Why this is important:
# - Simplifies access control (one mechanism: IAM + bucket policy, not ACLs)
# - Prevents ACL-based misconfigurations that could expose state files
# - Aligns with AWS security best practices (ACLs are legacy)
# - Required for some AWS features (e.g., S3 Object Lambda)
#
# For Terraform state buckets:
# - All state files are owned by the bucket owner (Management account)
# - Access is controlled via bucket policy (allowed_principal_arn_patterns)
# - No risk of ACL-based access leaks
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Enable versioning to keep history of Terraform state files
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle rule to manage old state file versions
# 
# Why this is needed:
# - Versioning is enabled to protect against accidental deletion/corruption
# - However, old versions accumulate over time and increase storage costs
# - Terraform state files are typically small, but versions can add up over months/years
# - This rule automatically deletes non-current versions older than 90 days
#
# Benefits:
# - Reduces storage costs by cleaning up old versions automatically
# - Maintains recent version history (90 days) for recovery purposes
# - Prevents unbounded storage growth from version accumulation
# - 90 days is typically sufficient for recovery scenarios (most issues are discovered quickly)
#
# Note: This only affects non-current versions. The current version is never deleted
# by this rule, ensuring active state files are always preserved.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90  # Delete non-current versions older than 90 days
    }
  }
}

# Enable server-side encryption (AES-256)
# All objects in the bucket are encrypted at rest using AWS-managed keys.
# This is required for Terraform state files containing sensitive infrastructure data.
# AES-256 uses AWS-managed encryption keys (no KMS key needed, no additional cost).
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # AWS-managed encryption (no KMS key needed)
    }
  }
}

# Prevent any form of public access.
# Acts as a safety net against misconfiguration
#
# IMPORTANT: This is DIFFERENT from BucketOwnerEnforced!
#
# BucketOwnerEnforced (above):
#   - Disables ACLs (old access control mechanism)
#   - Does NOT protect against public bucket policy
#
# bucket_public_access_block (this):
#   - Blocks public access via bucket policy (new access control mechanism)
#   - Protects even if bucket policy has Principal = "*" without conditions
#
# Why both are needed:
# 1. BucketOwnerEnforced protects against ACL-based leaks
# 2. bucket_public_access_block protects against bucket policy misconfigurations
#
# Example risk without this:
#   - Someone accidentally modifies bucket policy
#   - Removes the aws:PrincipalArn condition
#   - Bucket becomes publicly accessible (Principal = "*" without restrictions)
#   - This setting prevents that even if policy is misconfigured
#
# For Terraform state buckets:
#   - State files contain sensitive infrastructure information
#   - Must NEVER be publicly accessible
#   - This is a critical security layer
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  # Block new public ACLs and public objects
  block_public_acls = true
  
  # Ignore existing public ACLs (they're already disabled by BucketOwnerEnforced)
  ignore_public_acls = true
  
  # Block new public bucket policies
  block_public_policy = true
  
  # Restrict any public bucket policies (even if they exist)
  restrict_public_buckets = true
}

# ------------------------------------------------------------
# Bucket policy
# ------------------------------------------------------------
# Resource-based policy defining which principals the bucket trusts.
# Even if other identities have S3 permissions, access is denied
# unless explicitly allowed here.
#
# IMPORTANT AWS NOTE:
# S3 bucket policies have limitations:
# 1. Cannot use wildcards in Principal field directly (e.g., "arn:aws:iam::*:role/*")
# 2. Cannot reference IAM roles that don't exist at policy creation time
# 3. This causes "MalformedPolicy: Invalid principal" errors due to IAM/S3 eventual consistency
#
# Problem scenario:
#   - Terraform creates bucket policy BEFORE creating TerraformExecutionRole-* in member accounts
#   - Bucket policy references roles that don't exist yet
#   - S3 validates policy and rejects it: "Invalid principal"
#
# Solution:
#   - Use Principal = "*" (allows any principal)
#   - Restrict access via Condition on aws:PrincipalArn (pattern matching)
#   - This defers principal validation to runtime (when access is attempted)
#
# This pattern is production-safe and avoids ordering/dependency issues
# between IAM role creation (in member accounts) and S3 policy attachment (in Management account).
data "aws_iam_policy_document" "this" {
  
  # Statement 1: Allow access for trusted IAM roles
  # This statement grants access to multiple TerraformExecutionRole-* roles
  # from different accounts and SSO roles from Management account.
  statement {
    sid    = "AllowTerraformStateAccess"
    effect = "Allow"
    
    # We allow any AWS principal here,
    # but restrict access via the aws:PrincipalArn condition below.
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    # Minimal permissions required by Terraform backend
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    # Applies to the bucket itself and all objects within it
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*"
    ]

    # Allow access ONLY if the calling principal
    # matches one of the allowed ARN patterns.
    #
    # NOTE:
    # This bucket policy is a coarse allowlist. It admits multiple
    # TerraformExecutionRole-* principals, while fine-grained scoping
    # (e.g., dev/* vs prod/*) is enforced in each role's IAM policy.
    #
    # This avoids direct Principal references and
    # works reliably with IAM eventual consistency.
    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = var.allowed_principal_arn_patterns
    }
  }

  # Statement 2: Enforce TLS/HTTPS (Security Best Practice)
  # Denies any request that does not use encryption in transit.
  statement {
    sid    = "EnforceTLS"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"] 
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# Attach the generated bucket policy to S3
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json
}
