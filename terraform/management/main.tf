# ------------------------------------------------------------
# AWS Organization discovery
# ------------------------------------------------------------
data "aws_organizations_organization" "this" {}
data "aws_caller_identity" "current" {}


locals {
  # Build a map: env -> account_id
  # Iterates through AWS Organizations accounts, removes project prefix from account name to get env name,
  # and creates a map only for accounts that match the environments list.
  # 
  # IMPORTANT: Only accounts that START WITH the project prefix are included.
  # This prevents including accounts like "dev" or "other-project-dev" that don't belong to this project.
  #
  # Example: "autoscaling-eks-dev" (ID: 123456789012) → { "dev" => "123456789012" }
  # Example: "dev" → excluded (doesn't start with project prefix)
  # Example: "other-project-dev" → excluded (doesn't start with project prefix)
  env_accounts = {
    for account in data.aws_organizations_organization.this.accounts:
    replace(account.name, "${var.project}-", "") => account.id
    if startswith(account.name, "${var.project}-") &&
       contains(var.environments, replace(account.name, "${var.project}-", ""))
  }

  terraform_execution_role_arns = [
    for env, account_id in local.env_accounts :
    "arn:aws:iam::${account_id}:role/TerraformExecutionRole-${env}"
  ]

  # Allow access to backend/locks for:
  # 1. TerraformExecutionRole-* from workload accounts (dev, stage, prod)
  #    - These roles are created in member accounts via cross-account assume_role
  #    - Used for Terraform execution in workload accounts (not in Management)
  # 2. SSO roles from Management account
  #    - Management account Terraform runs directly via SSO credentials (PlatformAdmin)
  #    - No TerraformExecutionRole-management is created (by design - see iam-design.md)
  #    - SSO roles are used when PlatformAdmins run Terraform from Management account
  backend_allowed_principal_arn_patterns = concat(
    local.terraform_execution_role_arns,
    [
      # SSO roles from Management account (used when Terraform runs directly via SSO)
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/*"
    ]
  )
}

# ------------------------------------------------------------
# Centralized backend + execution roles
# ------------------------------------------------------------
module "management_backend" {
  source = "../modules/s3-tf-backend"

  bucket_name = "tf-state-${var.project}-management-${data.aws_caller_identity.current.account_id}"
  allowed_principal_arn_patterns = local.backend_allowed_principal_arn_patterns

  tags = {
    Project     = var.project
    Environment = "management"
    ManagedBy   = "terraform"
  }
}

module "management_locks" {
  source = "../modules/dynamodb-tf-locks"

  table_name = "terraform-locks-${var.project}-management"
  allowed_principal_arn_patterns = local.backend_allowed_principal_arn_patterns

  tags = {
    Project     = var.project
    Environment = "management"
    ManagedBy   = "terraform"
  }
}

module "terraform_role_dev" {
  count = contains(keys(local.env_accounts), "dev") ? 1 : 0

  source = "../modules/iam-terraform-role"
  providers = {
    aws = aws.dev
  }

  role_name  = "TerraformExecutionRole-dev"
  aws_region = var.aws_region
  account_id = local.env_accounts["dev"]

  # This role is assumed only by IAM Identity Center (SSO) generated roles.
  # When users are assigned to this AWS account via SSO, AWS creates
  # temporary IAM roles under aws-reserved/sso.amazonaws.com/.
  # These role names are unpredictable, so we trust the entire SSO role path.
  # Actual access is controlled by SSO assignments and this role's IAM policy.
  trusted_principal_arn_patterns = [
    "arn:aws:iam::${local.env_accounts["dev"]}:role/aws-reserved/sso.amazonaws.com/*"
  ]

  state_bucket_arn = module.management_backend.bucket_arn
  lock_table_arn   = module.management_locks.table_arn
  # Prefix guard: ties this role to dev/* in S3/DynamoDB.
  state_key_prefix = "dev/"

  # Dev: Broad permissions for rapid development
  permissions_mode     = "broad"
  require_mfa          = false
  max_session_duration = 28800 # 8 hours
}

module "terraform_role_stage" {
  count = contains(keys(local.env_accounts), "stage") ? 1 : 0

  source = "../modules/iam-terraform-role"
  providers = {
    aws = aws.stage
  }

  role_name  = "TerraformExecutionRole-stage"
  aws_region = var.aws_region
  account_id = local.env_accounts["stage"]

  # The same logic here with Trust policy as above in the dev case.
  #
  # IMPORTANT: Stage allows SSO access for SMB/startup teams.
  # This is an intentional design decision that balances security with operational speed:
  # - Stage uses hardened permissions (same as Prod) to prevent accidental production-like changes
  # - SSO access enables manual testing and rapid iteration for small teams
  # - Clear separation: Stage = SSO allowed, Prod = CI-only (when implemented)
  # Actual access is controlled by SSO assignments and this role's IAM policy.
  trusted_principal_arn_patterns = [
    "arn:aws:iam::${local.env_accounts["stage"]}:role/aws-reserved/sso.amazonaws.com/*"
  ]

  state_bucket_arn = module.management_backend.bucket_arn
  lock_table_arn   = module.management_locks.table_arn
  # Prefix guard: ties this role to stage/* in S3/DynamoDB.
  state_key_prefix = "stage/"

  # Stage: Hardened permissions with MFA requirement
  permissions_mode     = "hardened"
  require_mfa          = true
  max_session_duration = 3600 # 1 hour
}

module "terraform_role_prod" {
  count = contains(keys(local.env_accounts), "prod") ? 1 : 0

  source = "../modules/iam-terraform-role"
  providers = {
    aws = aws.prod
  }

  role_name  = "TerraformExecutionRole-prod"
  aws_region = var.aws_region
  account_id = local.env_accounts["prod"]

  # NOTE: Prod will be CI-only (GitHub OIDC) when implemented.
  # Currently uses SSO trust temporarily.
  trusted_principal_arn_patterns = [
    "arn:aws:iam::${local.env_accounts["prod"]}:role/aws-reserved/sso.amazonaws.com/*"
  ]

  state_bucket_arn = module.management_backend.bucket_arn
  lock_table_arn   = module.management_locks.table_arn
  # Prefix guard: ties this role to prod/* in S3/DynamoDB.
  state_key_prefix = "prod/"

  # Prod: Hardened permissions with MFA requirement and short session duration
  # NOTE: AWS requires minimum 3600 seconds (1 hour) for IAM role max_session_duration.
  # For CI/CD (GitHub OIDC), consider increasing to 14400 (4 hours) for pipeline execution.
  permissions_mode     = "hardened"
  require_mfa          = true
  max_session_duration = 3600 # 1 hour (AWS minimum; increase for CI/CD if needed)
}
