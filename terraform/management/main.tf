# ------------------------------------------------------------
# AWS Organization discovery
# ------------------------------------------------------------
data "aws_organizations_organization" "this" {}

# Build a map: env -> account_id
locals {
  accounts = {
    for account in data.aws_organizations_organization.this.accounts:
    account.name => account.id
    if contains(var.environments, replace(account.name, "${var.project}-", ""))
  }
}

# ------------------------------------------------------------
# Per-environment backend + execution role
# ------------------------------------------------------------
module "backend" {
  for_each = locals.accounts
 

  source = "../modules/s3-tf-backend"
  

  bucket_name  = "tf-state-${var.project}-${each.key}-${each.value}" 
  allowed_role = "arn:aws:iam::${each.value}:role/TerraformExecutionRole-${each.key}"


  tags = {
    Project     = var.project
    Environment = each.key
    ManagedBy   = "terraform"
  }
}


module "locks" {
  for_each = local.accounts


  source   = "../modules/dynamodb-tf-locks"


  table_name = "terraform-locks-${var.project}-${each.key}" 

  
  tags = {
    Project     = var.project
    Environment = each.key
    ManagedBy   = "terraform"
  }
}

module "terraform_role" {
  for_each = local.accounts


  source = "../modules/iam-terraform-role"


  role_name  = "TerraformExecutionRole-${each.key}"
  aws_region = var.aws_region
  account_id = each.value


  # This role is assumed only by IAM Identity Center (SSO) generated roles.
  # When users are assigned to this AWS account via SSO, AWS creates
  # temporary IAM roles under aws-reserved/sso.amazonaws.com/.
  # These role names are unpredictable, so we trust the entire SSO role path.
  # Actual access is controlled by SSO assignments and this role’s IAM policy.
  trusted_role_arns = [
    "arn:aws:iam::${each.value}:role/aws-reserved/sso.amazonaws.com/*"
  ]

 
  state_bucket_arn = module.backend[each.key].bucket_arn
  lock_table_arn   = module.locks[each.key].table_arn

}
