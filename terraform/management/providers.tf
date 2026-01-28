terraform {
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" 
    }
  }
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
