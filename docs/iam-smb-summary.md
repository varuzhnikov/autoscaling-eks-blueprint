# IAM for SMB/Startups — Summary

## Purpose

Provide a minimal, production‑sane IAM model for multi‑account AWS
using Terraform and SSO, suitable for SMBs and startups.

## Key Principles

- No IAM users or long‑lived access keys
- Centralized identity via IAM Identity Center (SSO)
- Centralized Terraform state (S3 + DynamoDB) in Management
- Least‑privilege where it matters (state access and prod write)

## Account Model

- Management: IAM control plane, Terraform management (operated by PlatformAdmins via SSO)
- Dev / Stage / Prod: workloads only

## How Terraform Runs

**For workload accounts (Dev/Stage/Prod):**
1) Human authenticates via SSO (PlatformAdmin or DevEngineers)
2) Terraform uses a dedicated execution role (`TerraformExecutionRole-*`) in each account
3) State stored centrally with per‑environment key prefixes

**For Management account:**
- Terraform runs directly via SSO credentials (no dedicated execution role)
- PlatformAdmins authenticate via SSO and run Terraform directly

## Roles (SMB‑Friendly)

- `TerraformExecutionRole-dev|stage|prod`
  - Access to centralized state (dev/*, stage/*, prod/*)
  - No IAM write permissions
  - Dev & Stage: SSO access allowed (Stage uses hardened permissions for safety)
  - Prod: SSO temporarily, will be CI-only (GitHub OIDC) when implemented

IAM changes in workload accounts are applied from Management account using
cross-account assume role (`OrganizationAccountAccessRole` or equivalent).
This provides centralized control even though PlatformAdmins may have SSO
AdministratorAccess in member accounts.

**Note:** Stage allows SSO access for manual testing in SMB/startup environments.
This balances security (hardened permissions) with operational speed for small teams.

## State Safety

- One S3 bucket, one DynamoDB table (Management account)
- State key prefixes enforced per role (dev/*, stage/*, prod/*)
- DynamoDB lock IDs follow the state key
- Management account Terraform runs directly via SSO (no dedicated execution role)

## Bootstrap & Daily Use (High‑Level)

- Bootstrap:
  - `terraform init -reconfigure`
  - `terraform apply` from Management (SSO)
- Daily:
  - `aws sso login --profile platform-admin-management --no-browser`
  - `terraform plan/apply`

## Why This Is “Enough” for SMB

- Clean separation of accounts
- Safe Terraform execution without IAM users
- Centralized state with scoped access
- Minimal role sprawl, easier to maintain

This design can be upgraded later with stricter controls
if compliance requirements grow.
