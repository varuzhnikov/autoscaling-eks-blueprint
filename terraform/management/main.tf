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

  # Assumed-role ARN patterns (for resource policies that check assumed-role ARN via aws:PrincipalArn)
  # When a role is assumed via AWS profile or assume_role, aws:PrincipalArn has format:
  # arn:aws:sts::<account-id>:assumed-role/<role-name>/<session-name>
  # Session names are unpredictable (e.g., "aws-go-sdk-..."), so we use wildcard pattern
  terraform_execution_assumed_role_arn_patterns = [
    for env, account_id in local.env_accounts :
    "arn:aws:sts::${account_id}:assumed-role/TerraformExecutionRole-${env}/*"
  ]

  # IAM role ARN patterns.
  #
  # In some AWS services/policy-condition evaluations, `aws:PrincipalArn`
  # may be evaluated in IAM-role ARN format even when the caller uses
  # STS assumed-role credentials.
  # We include both formats to make S3 bucket policy principal matching robust.
  terraform_execution_role_arn_patterns = [
    for env, account_id in local.env_accounts :
    "arn:aws:iam::${account_id}:role/TerraformExecutionRole-${env}"
  ]

  backend_allowed_principal_arn_patterns = concat(
    local.terraform_execution_assumed_role_arn_patterns,
    local.terraform_execution_role_arn_patterns,
    module.backend_access_roles.assumed_role_arn_patterns,
    module.backend_access_roles.role_arn_patterns,
    ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/*"]
  )

  terraform_role_settings = {
    dev = {
      permissions_mode     = "broad"
      require_mfa          = false
      max_session_duration = 28800
    }
    stage = {
      permissions_mode     = "hardened"
      require_mfa          = true
      max_session_duration = 3600
    }
    prod = {
      permissions_mode     = "hardened"
      require_mfa          = true
      max_session_duration = 3600
    }
  }
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

module "backend_access_roles" {
  source = "../modules/iam-backend-access-role"

  env_accounts          = local.env_accounts
  management_account_id = data.aws_caller_identity.current.account_id
  state_bucket_arn      = module.management_backend.bucket_arn
  lock_table_arn        = module.management_locks.table_arn
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

  permissions_mode     = local.terraform_role_settings["dev"].permissions_mode
  require_mfa          = local.terraform_role_settings["dev"].require_mfa
  max_session_duration = local.terraform_role_settings["dev"].max_session_duration
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

  permissions_mode     = local.terraform_role_settings["stage"].permissions_mode
  require_mfa          = local.terraform_role_settings["stage"].require_mfa
  max_session_duration = local.terraform_role_settings["stage"].max_session_duration
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

  permissions_mode     = local.terraform_role_settings["prod"].permissions_mode
  require_mfa          = local.terraform_role_settings["prod"].require_mfa
  max_session_duration = local.terraform_role_settings["prod"].max_session_duration
}

# Allow only dev execution role to assume dev backend access role in management.
data "aws_iam_policy_document" "allow_assume_backend_dev" {
  count = contains(keys(local.env_accounts), "dev") ? 1 : 0

  statement {
    sid     = "AssumeDevBackendStateAccessRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/TerraformStateAccessRole-dev"
    ]
  }
}

resource "aws_iam_policy" "allow_assume_backend_dev" {
  count    = contains(keys(local.env_accounts), "dev") ? 1 : 0
  name     = "TerraformExecutionRole-dev-assume-backend"
  policy   = data.aws_iam_policy_document.allow_assume_backend_dev[0].json
  provider = aws.dev
}

resource "aws_iam_role_policy_attachment" "allow_assume_backend_dev" {
  count      = contains(keys(local.env_accounts), "dev") ? 1 : 0
  role       = "TerraformExecutionRole-dev"
  policy_arn = aws_iam_policy.allow_assume_backend_dev[0].arn
  provider   = aws.dev
}
