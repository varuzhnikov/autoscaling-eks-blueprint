terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" 
    }
  }

  backend "s3" {}
}

# ------------------------------------------------------------
# Management account provider
# ------------------------------------------------------------
# All Terraform in this directory is executed from the
# Management account using SSO (PlatformAdmins).
#
# This provider is used ONLY to query AWS Organizations
# and to assume roles into target accounts.
provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------------
# Target account providers (SMB-friendly)
# ------------------------------------------------------------
# Use cross-account assume role (OrganizationAccountAccessRole or custom) to manage
# IAM roles/policies in member accounts from Management account.
# This provides centralized control even though PlatformAdmins may have SSO
# AdministratorAccess in member accounts.
provider "aws" {
  alias  = "dev"
  region = var.aws_region

  assume_role {
    role_arn = format("arn:aws:iam::%s:role/%s", local.env_accounts.dev, var.bootstrap_role_name)
  }
}

provider "aws" {
  alias  = "stage"
  region = var.aws_region

  assume_role {
    role_arn = format("arn:aws:iam::%s:role/%s", local.env_accounts.stage, var.bootstrap_role_name)
  }
}

provider "aws" {
  alias  = "prod"
  region = var.aws_region

  assume_role {
    role_arn = format("arn:aws:iam::%s:role/%s", local.env_accounts.prod, var.bootstrap_role_name)
  }
}
