terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    # Backend configuration is provided via backend.hcl
    # bucket, key, region, dynamodb_table, encrypt
  }
}

provider "aws" {
  region = var.aws_region
}
