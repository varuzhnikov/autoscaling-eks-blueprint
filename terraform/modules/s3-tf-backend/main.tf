# ------------------------------------------------------------
# Terraform state S3 backend module
# ------------------------------------------------------------
# This module creates a secure S3 bucket for storing Terraform remote state.
# The bucket is private by default and access is restricted to a single IAM role.
# ACL-based access is disabled; IAM roles and bucket policy are used instead.

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
# Access control is handled exclusively via IAM and bucket policy.
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

# Enable server-side encryption (AES-256)
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Prevent any form of public access.
# Acts as a safety net against misconfiguration
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------
# Bucket policy
# ------------------------------------------------------------
# Resource-based policy defining which principals the bucket trusts.
# Even if other identities have S3 permissions, access is denied
# unless explicitly allowed here.
data "aws_iam_policy_document" "this" {
  
  # Statement 1: Standard access for the allowed IAM Role
  statement {
    sid    = "AllowTerraformStateAccess"
    effect = "Allow"
    
    # Only the specified IAM role can access the Terraform state
    principals {
      type        = "AWS"
      identifiers = [var.allowed_role]
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
