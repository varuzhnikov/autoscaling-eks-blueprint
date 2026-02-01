# TerraformExecutionRole Permissions Examples

This document provides examples of how to customize permissions for `TerraformExecutionRole` in different environments.

## Permission Modes

### 1. Broad Mode (Dev)

**Purpose:** Fast development iteration with wide permissions (PowerUserAccess-like)

**Configuration:**
```hcl
module "terraform_role_dev" {
  # ... other parameters ...
  
  permissions_mode     = "broad"
  require_mfa          = false
  max_session_duration = 28800 # 8 hours
}
```

**What it includes:**
- Most AWS services (EC2, EKS, ECS, RDS, S3, Lambda, etc.)
- IAM read-only access (no write permissions)
- Region-restricted to specified region
- No MFA requirement

**Use case:** Development environment where speed of iteration is prioritized.

---

### 2. Hardened Mode (Stage/Prod)

**Purpose:** Minimal permissions for production safety

**Configuration:**
```hcl
module "terraform_role_stage" {
  # ... other parameters ...
  
  permissions_mode     = "hardened"
  require_mfa          = true
  max_session_duration = 3600 # 1 hour
}

module "terraform_role_prod" {
  # ... other parameters ...
  
  permissions_mode     = "hardened"
  require_mfa          = true
  max_session_duration = 3600 # 1 hour (AWS minimum requirement)
}
```

**What it includes:**
- Minimal EC2 permissions (VPC, subnets, routing, instances)
- EKS cluster and nodegroup management
- IAM read-only access (Get*, List*, Describe*)
- CloudWatch Logs management (CreateLogGroup, DeleteLogGroup, etc.)
- CloudWatch alarms management
- Tagging permissions (TagResources, UntagResources)
- Service Quotas (read-only)
- Region-restricted to specified region
- MFA required

**Use case:** Stage and Production environments where security is prioritized.

---

### 3. Custom Mode

**Purpose:** Define your own permissions

**Configuration:**
```hcl
module "terraform_role_custom" {
  # ... other parameters ...
  
  permissions_mode = "custom"
  additional_permissions = [
    {
      sid    = "CustomS3Access"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ]
      resources = [
        "arn:aws:s3:::my-bucket/*"
      ]
      conditions = [
        {
          test     = "StringEquals"
          variable = "s3:x-amz-server-side-encryption"
          values   = ["AES256"]
        }
      ]
    },
    {
      sid    = "CustomLambdaAccess"
      effect = "Allow"
      actions = [
        "lambda:CreateFunction",
        "lambda:UpdateFunctionCode",
        "lambda:DeleteFunction",
        "lambda:GetFunction"
      ]
      resources = [
        "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:*"
      ]
    }
  ]
}
```

---

## Policy Hardening Workflow

### Step 1: Start with Broad Permissions (Dev)

Use `permissions_mode = "broad"` in Dev to allow Terraform to work without restrictions.

### Step 2: Monitor Actual Usage

Enable CloudTrail and review API calls made by TerraformExecutionRole in Dev:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=TerraformExecutionRole-dev \
  --start-time 2024-01-01T00:00:00Z
```

### Step 3: Use IAM Access Analyzer

Review IAM Access Analyzer findings to identify unused permissions:

```bash
aws accessanalyzer list-findings \
  --analyzer-arn arn:aws:access-analyzer:region:account-id:analyzer/analyzer-id
```

### Step 4: Create Hardened Policy

Based on actual usage, create a minimal policy. Start with the default hardened permissions and add only what's needed.

### Step 5: Apply to Stage/Prod

Use the hardened permissions in Stage and Prod:

```hcl
permissions_mode = "hardened"
require_mfa      = true
```

---

## Common Permission Patterns

### EKS Cluster Management

If you need additional EKS permissions:

```hcl
additional_permissions = [
  {
    sid    = "EKSAddonManagement"
    effect = "Allow"
    actions = [
      "eks:CreateAddon",
      "eks:DeleteAddon",
      "eks:DescribeAddon",
      "eks:ListAddons"
    ]
    resources = ["*"]
  }
]
```

### RDS Database Management

For RDS resources:

```hcl
additional_permissions = [
  {
    sid    = "RDSManagement"
    effect = "Allow"
    actions = [
      "rds:CreateDBInstance",
      "rds:DeleteDBInstance",
      "rds:ModifyDBInstance",
      "rds:DescribeDBInstances"
    ]
    resources = ["*"]
  }
]
```

### S3 Application Buckets

For application S3 buckets (not state):

```hcl
additional_permissions = [
  {
    sid    = "ApplicationS3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::app-bucket-*",
      "arn:aws:s3:::app-bucket-*/*"
    ]
  }
]
```

---

## Best Practices

1. **Start Broad, Harden Later**
   - Use `broad` mode in Dev initially
   - Monitor actual usage
   - Create hardened policies based on real needs

2. **Use MFA for Production**
   - Always set `require_mfa = true` for Stage/Prod
   - This adds an extra security layer

3. **Limit Session Duration**
   - Dev: 8 hours (28800 seconds)
   - Stage: 1 hour (3600 seconds)
   - Prod: 1 hour (3600 seconds) - AWS minimum requirement

4. **Region Restrictions**
   - All permissions are automatically restricted to the specified region
   - This prevents accidental cross-region operations

5. **No IAM Write Permissions**
   - TerraformExecutionRole never has IAM write permissions
   - IAM changes are applied from Management account only

6. **Regular Review**
   - Review CloudTrail logs quarterly
   - Update hardened permissions based on actual usage
   - Remove unused permissions

---

## Troubleshooting

### "Access Denied" Errors

If Terraform fails with access denied:

1. Check CloudTrail logs to see which action was denied
2. Add the required permission to `additional_permissions` (if using custom mode)
3. Or update the hardened permissions in the module (if using hardened mode)

### MFA Required Errors

If you see MFA requirement errors:

1. Ensure MFA is enabled for your SSO user
2. Use `aws sso login` to authenticate with MFA
3. Or temporarily set `require_mfa = false` for testing (not recommended for Prod)

### Session Expired

If your session expires too quickly:

1. Check `max_session_duration` setting
2. Increase if needed (max 12 hours for AWS)
3. Re-authenticate via `aws sso login`
