# First Run: Local Backend + Migration Method

## Overview

This document describes the initial Terraform setup using a **local backend for the first apply**, then migrating state to S3. This method allows Terraform to create all resources automatically, including the S3 bucket and DynamoDB table for state storage.

## Prerequisites

1. ✅ AWS Organizations created
2. ✅ Member accounts created through Organizations (dev, stage, prod)
3. ✅ IAM Identity Center enabled in Management account
4. ✅ Permission Set "PlatformAdmin" created with AdministratorAccess
5. ✅ You are assigned to Management account via SSO with PlatformAdmin
6. ✅ `OrganizationAccountAccessRole` exists in each member account

## Step-by-Step Guide

### Step 1: Comment Out Backend in providers.tf

**Open `terraform/management/providers.tf`:**

**BEFORE:**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" 
    }
  }

  backend "s3" {}  # ← Comment this out
}
```

**AFTER:**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" 
    }
  }

  # backend "s3" {}  # ← Temporarily commented out for first apply
}
```

**Save the file.**

**Important:**
- Terraform will use local backend (state in `terraform.tfstate` file)
- This is a temporary solution only for the first apply

---

### Step 2: Login to Management Account via SSO

```bash
# Login to Management account
aws sso login --profile platform-admin-management --no-browser
export AWS_PROFILE=platform-admin-management

# Verify you're in the correct account
aws sts get-caller-identity
```

---

### Step 3: First terraform init (Without Backend)

```bash
cd terraform/management

# Initialize without backend (uses local backend)
terraform init
```

**Expected output:**
```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.x.x...
...

Terraform has been successfully initialized!
```

**What happens:**
- ✅ Terraform initializes WITHOUT S3 backend
- ✅ State will be stored locally in `terraform.tfstate` file (created after apply)
- ✅ Providers are loaded and ready to use

**Important:**
- `terraform.tfstate` file is **NOT created** after `terraform init`
- State file is created only after `terraform apply` or `terraform plan` (if there are changes)
- This is normal behavior - init only sets up the working directory

**Verify:**
```bash
# After terraform init, file doesn't exist yet - this is normal
# File will appear after terraform plan or terraform apply
ls -la terraform.tfstate  # May not exist - this is OK
```

---

### Step 4: First terraform plan

```bash
terraform plan
```

**What you'll see:**
- Terraform will show a plan to create all resources:
  - S3 bucket for state
  - DynamoDB table for locks
  - TerraformExecutionRole-* in member accounts

**Review the plan:**
- Verify that correct resources will be created
- Check bucket and table names (they will be used later)

**Example output:**
```
Plan: 8 to add, 0 to change, 0 to destroy.

  # module.management_backend.aws_s3_bucket.this will be created
  + resource "aws_s3_bucket" "this" {
      + bucket = "tf-state-autoscaling-eks-management-123456789012"
      ...
    }

  # module.management_locks.aws_dynamodb_table.this will be created
  + resource "aws_dynamodb_table" "this" {
      + name = "terraform-locks-autoscaling-eks-management"
      ...
    }

  ...
```

**Record the names of resources to be created:**
- Bucket name: `tf-state-autoscaling-eks-management-<YOUR-ACCOUNT-ID>`
- DynamoDB table name: `terraform-locks-autoscaling-eks-management`

---

### Step 5: First terraform apply

```bash
terraform apply
```

**Terraform will ask for confirmation:**
```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: 
```

**Type `yes` and press Enter.**

**What happens:**
- ✅ Terraform creates S3 bucket
- ✅ Terraform creates DynamoDB table
- ✅ Terraform creates TerraformExecutionRole-* in member accounts
- ✅ State is saved locally in `terraform.tfstate`

**After successful apply:**
```
Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
```

**Verify created resources:**
```bash
# Check bucket
aws s3 ls | grep tf-state

# Check DynamoDB table
aws dynamodb list-tables | grep terraform-locks

# Check state (locally)
cat terraform.tfstate | jq '.resources[].type'
```

---

### Step 6: Uncomment Backend in providers.tf

**Open `terraform/management/providers.tf`:**

**BEFORE:**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" 
    }
  }

  # backend "s3" {}  # ← Temporarily commented out
}
```

**AFTER:**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" 
    }
  }

  backend "s3" {}  # ← Uncommented
}
```

**Save the file.**

---

### Step 7: Create backend.hcl with Created Resource Names

**Important**: Use EXACTLY the same names that Terraform created in Step 5!

```bash
# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Create backend.hcl
cat > backend.hcl <<EOF
bucket         = "tf-state-autoscaling-eks-management-${ACCOUNT_ID}"
key            = "management/terraform.tfstate"
region         = "eu-central-1"
dynamodb_table = "terraform-locks-autoscaling-eks-management"
encrypt        = true
EOF

# Verify contents
cat backend.hcl
```

**Verify that names match:**
- Bucket name must match the one created in Step 5
- DynamoDB table name must match the one created in Step 5

**To verify exact names:**
```bash
# Check bucket name from state
terraform state show module.management_backend.aws_s3_bucket.this | grep bucket

# Check table name from state
terraform state show module.management_locks.aws_dynamodb_table.this | grep name
```

---

### Step 8: Migrate State from Local to S3

**⚠️ IMPORTANT: Create a backup of local state before migration!**

```bash
# Create backup of local state
cp terraform.tfstate terraform.tfstate.backup

# Verify backup was created
ls -la terraform.tfstate*
```

**Now migrate state:**

```bash
terraform init -migrate-state -backend-config=backend.hcl
```

**Terraform will ask:**
```
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend to the
  newly configured "s3" backend. No existing state was found in the newly
  configured "s3" backend. Do you want to copy this state to the new "s3" backend?
  Enter "yes" to copy and "no" to start with an empty state.

  Enter a value:
```

**Type `yes` and press Enter.**

**What happens:**
- ✅ Terraform copies state from `terraform.tfstate` (local) to S3
- ✅ State is now stored in S3 bucket
- ✅ Terraform configures backend for future use

**Expected output:**
```
Initializing the backend...
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend to the
  newly configured "s3" backend. No existing state was found in the newly
  configured "s3" backend. Do you want to copy this state to the new "s3" backend?
  Enter "yes" to copy and "no" to start with an empty state.

  Enter a value: yes

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins...
- Reusing previous version of hashicorp/aws from the dependency lock file
- Using previously-installed hashicorp/aws v6.x.x

Terraform has been successfully initialized!
```

---

### Step 9: Verification After Migration

**Verify that state is in S3:**

```bash
# Check state in S3
aws s3 ls s3://tf-state-autoscaling-eks-management-<YOUR-ACCOUNT-ID>/management/

# Should see terraform.tfstate file
```

**Verify that Terraform sees resources:**

```bash
# Check state list
terraform state list

# Should see all created resources:
# module.management_backend.aws_s3_bucket.this
# module.management_locks.aws_dynamodb_table.this
# module.terraform_role_dev.aws_iam_role.this
# etc.
```

**Verify that local state is no longer used:**

```bash
# Local state should be empty or removed
# (Terraform may leave it for backup)
ls -la terraform.tfstate
```

**Try terraform plan (should work with S3 backend):**

```bash
terraform plan

# Should show: "No changes. Your infrastructure matches the configuration."
```

---

### Step 10: Cleanup (Optional)

**After successful migration, you can remove local state:**

```bash
# ⚠️ WARNING: Delete only after verifying that S3 backend works!

# Create final backup
cp terraform.tfstate terraform.tfstate.local-backup

# Remove local state (Terraform no longer uses it)
rm terraform.tfstate

# Or move to backup directory
mkdir -p .backup
mv terraform.tfstate* .backup/
```

---

## Important Notes

### 1. Backup Before Migration

**ALWAYS create a backup before migrating state!**

```bash
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d-%H%M%S)
```

### 2. Names Must Match Exactly

**Bucket and table created by Terraform must have EXACTLY the same names** as specified in `backend.hcl`.

**Verify:**
```bash
# After terraform apply, check names
terraform state show module.management_backend.aws_s3_bucket.this | grep bucket
terraform state show module.management_locks.aws_dynamodb_table.this | grep name

# Use these names in backend.hcl
```

### 3. If Migration Fails

**If something goes wrong during migration:**

```bash
# 1. Restore local state from backup
cp terraform.tfstate.backup terraform.tfstate

# 2. Comment out backend again
# (in providers.tf)

# 3. Reinitialize with local backend
terraform init

# 4. Verify all resources are visible
terraform state list

# 5. Try migration again
```

### 4. Verification Before Deleting Local State

**Before deleting local state, ensure:**

```bash
# 1. State exists in S3
aws s3 ls s3://<bucket-name>/management/terraform.tfstate

# 2. Terraform sees resources
terraform state list

# 3. Terraform plan works
terraform plan  # Should show "No changes"

# 4. Only then delete local state
```

---

## Checklist

- [ ] Backend commented out in providers.tf
- [ ] `terraform init` executed (local backend)
- [ ] `terraform plan` executed (verified resource names)
- [ ] `terraform apply` executed (created bucket, table, and roles)
- [ ] Backup of local state created
- [ ] Backend uncommented in providers.tf
- [ ] `backend.hcl` created with correct names
- [ ] State migrated (`terraform init -migrate-state`)
- [ ] Verified state is in S3
- [ ] Verified `terraform state list` works
- [ ] Verified `terraform plan` works
- [ ] (Optional) Local state deleted after verification

---

## Troubleshooting

### Error: "Backend configuration changed"

**Cause**: Backend already initialized with different parameters

**Solution**:
```bash
terraform init -reconfigure -backend-config=backend.hcl
```

### Error: "Failed to get existing workspaces: NoSuchBucket"

**Cause**: S3 bucket doesn't exist, but Terraform tries to use it

**Solution**: This shouldn't happen with this method, as bucket is created in Step 5. If it does:
1. Verify bucket was created: `aws s3 ls | grep tf-state`
2. Check bucket name in `backend.hcl` matches exactly
3. Verify you're in the correct AWS account

### Error: "AccessDenied" during migration

**Cause**: Insufficient permissions to write to S3 bucket

**Solution**:
1. Verify SSO credentials are valid: `aws sts get-caller-identity`
2. Verify bucket policy allows your SSO role
3. Check bucket exists and is accessible

---

## Summary

This method allows you to bootstrap Terraform infrastructure with full automation. The key steps are:

1. Use local backend for first apply
2. Create all resources (including bucket and table)
3. Migrate state from local to S3
4. Continue using S3 backend

**Remember**: Always create backups before migration and verify everything works before deleting local state!
