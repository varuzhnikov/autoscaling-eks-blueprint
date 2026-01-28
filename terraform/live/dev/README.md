# Terraform Management Layer

This directory bootstraps the Terraform control plane
for a multi-account AWS Organization.

It must be executed from the Management account
using IAM Identity Center (SSO) with PlatformAdmin access.

It creates, per environment:
- S3 bucket for Terraform state
- DynamoDB table for state locking
- Terraform execution IAM role

After this step, all infrastructure is managed
via assume-role and no root / IAM users are used.

