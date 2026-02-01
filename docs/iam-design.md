# IAM Design 
## Terraform & CI/CD Execution Model
| Field | Description |
| :--- | :--- |
| **Status** | Final / Production-ready blueprint |
| **Date** | January 2026 |
| **Audience** | Platform Engineers |
| **Scope** | IAM, identity, Terraform execution, CI/CD |
| **Out of scope** | EKS workloads, application runtime IAM |

## 1. Purpose

This document defines the **IAM and identity** architecture for a Terraform-managed AWS platform with:

- multiple AWS accounts
- centralized identity via IAM Identity Center (SSO)
- zero long-lived credentials
- **CI-only production changes via GitHub Actions OIDC**

The goal is to provide an IAM model that is:

- secure by default
- explainable to humans 
- scalable across environments
- realistic for real-world teams

This is a **blueprint**, not a legacy migration guide.

## 2. Core Principles

- No IAM users
- No access keys
- All access via short-lived STS credentials
- Centralized human identity (SSO)
- Clear separation between:
    - humans
    - CI/CD
    - Terraform execution
- Production is **CI-only**    

## 3. Account Model (AWS Organizations)

The platform uses **AWS Organizations**.

| Account | Purpose |
| :---    | :---    |
| **Management** | Identity & IAM control plane, Terraform management |
| **Dev** | Sandbox, experimentation |
| **Stage** | Pre-production validation |
| **Prod** | Production workloads |

Rules:
- IAM Identity Center exists **only in Management**
- No workloads run in Management
- Dev / Stage / Prod are fully isolated AWS accounts

## 4. Management Account (Control Plane)

The **Management account** is the IAM and Terraform **control plane**.

### What Management DOES

- Hosts IAM Identity Center (SSO)
- Manages:
    - users
    - groups
    - permission sets
- Runs **Terraform management layer**
- Creates and owns:
    - ```TerraformExecutionRole-...```
    - trust policies
    - Terraform state backends (S3 + DynamoDB)

### What Management DOES NOT Do

- Run applications
- Host EKS
- Store business data
- Serve traffic

### Why Management Uses SSO (PlatformAdmins)

The Management account is operated by PlatformAdmins via SSO. This is the correct approach because:

- **Management is a control plane**, not a workload account
- It contains no production data or applications
- PlatformAdmins (typically 1-2 trusted operators in SMB/startups) manage IAM roles across all accounts
- IAM changes in member accounts are applied from Management using cross-account assume role (`OrganizationAccountAccessRole` or equivalent bootstrap role)
- TerraformExecutionRole-* in workload accounts do NOT have IAM write permissions
- Centralized state bucket in Management is isolated via IAM policy prefix guards

This architecture provides sufficient security for SMB/startup teams while maintaining operational simplicity.

## 5. PlatformAdmins

### Who They Are

PlatformAdmins are **control-plane operators**.

Typical size:
- **1–2 people** (SMBs / startups)

### Responsibilities

- IAM Identity Center administration
- Terraform management layer
- Trust & permission model
- Emergency recovery

PlatformAdmins:
- authenticate via SSO
- never use root
- never use IAM users

## Initial Bootstrap Flow (One-Time)

### Step 1 — Enable AWS Organizations

From the root account (console):

```
AWS Organizations → Create organization
```
- All features enabled
- Root user used **only once**

### Step 2 — Create Accounts

From Management account:

```
AWS Organizations → Create account
```
Create:
- project-dev
- project-stage
- project-prod

### Step 3 — Enable IAM Identity Center

From Management:

```
IAM Identity Center → Enable
```

### Step 4 — Bootstrap member-account access (one-time)

Initial Terraform apply from Management account uses cross-account assume role
(```OrganizationAccountAccessRole``` by default) to create ```TerraformExecutionRole-*```
in member accounts.

**Note:** While PlatformAdmins may have AdministratorAccess via SSO in member accounts,
the architecture uses centralized management from Management account via assume role
for consistency and to maintain the control plane pattern.

## 7. IAM Identity Center Setup

### 7.1 Groups

Create:
- ```PlatformAdmins```
- ```DevEngineers```
- ```ReadOnly```

### 7.2 Permission Sets

Examples:

| **Permission Set** | **Policies** | **Used In** |
| :--- | :--- | :--- | 
| PlatformAdmin | AdministratorAccess | Management, Dev, Stage |
| DevAccess | PowerUserAccess or ReadOnly | Dev |
| ReadOnly | ReadOnlyAccess | Stage, Prod |

### 7.3 Assignments

| **Account** | **Group** | **Permission Set** |
| :--- | :--- | :--- |
| Management | PlatformAdmins | PlatformAdmin |
| Dev | PlatformAdmins | PlatformAdmin |
| Dev | DevEngineers | DevAccess |
| Stage | PlatformAdmins | PlatformAdmin |
| Prod | PlatformAdmins | ReadOnly |

Humans **never** get write access in Prod.

## Terraform Execution Model

Terraform **never runs as a human identity**.

It always runs under a dedicated IAM role.

### TerraformExecutionRole (Per Environment)

- ```TerraformExecutionRole-dev```
- ```TerraformExecutionRole-stage```
- ```TerraformExecutionRole-prod```

**Note:** Management account Terraform runs directly via SSO credentials (no dedicated execution role).

Terraform flow:

1. authenticate via SSO or CI
1. assume TerraformExecutionRole
1. talk to AWS APIs

IAM policy changes are applied from the Management account via
the member-account bootstrap role.

## 9. Trust Model

### 9.1 Dev & Stage — SSO Trust

```TerraformExecutionRole-dev``` and ```-stage``` trust ***SSO-generated IAM roles***.

SSO roles are created automatically under:

```
arn:aws:iam::<account-id>:role/aws-reserved/sso.amazonaws.com/*
```

What should be noticed:

- role names are unpredictable
- roles are created & destroyed by AWS
- cannot be hardcoded safely

Trust policy allows all ```SSO-generated roles in that account```.

Actual access is controlled by:

- IAM Identity Center assignments
- TerraformExecutionRole permissions

**Note for SMB/Startups:** Stage allows SSO access for manual testing and rapid iteration. This is an intentional design decision for smaller teams where:
- Stage is used for pre-production validation and manual testing
- Hardened permissions (same as Prod) prevent accidental production-like changes
- Clear separation: Stage = SSO allowed, Prod = CI-only (when implemented)
- This balances security with operational speed for small teams

### 9.2 Prod — CI/CD Only (GitHub OIDC)

**Target state:** CI/CD only via GitHub OIDC (not yet implemented)

**Current state:** Uses SSO trust temporarily (same as Dev/Stage) until CI/CD is implemented.

**Implementation status:** TODO - Will be implemented when CI/CD pipeline is set up

## 10. Permissions Model

### Key Rule

> **Trust defines _who can assume._**
> **IAM policy defines _what can be done._**

TerraformExecutionRole policy controls:
- allowed AWS services
- allowed regions
- resource scope

TerraformExecutionRole does not have IAM write permissions.
IAM changes are applied from the Management account.

## 11. Environment Strategy

| **Environment** | **Human Writes** | **Terraform Permissions** |
| :--- | :--- | :--- |
| Dev | Allowed (SSO) | Broad |
| Stage | Allowed (SSO) | Hardened |
| Prod | No (CI-only, when implemented) | Hardened |

Dev may drift.
Stage uses hardened permissions (same as Prod) but allows SSO access for manual testing in SMB/startup environments.
Prod must not drift and will be CI-only (GitHub OIDC) when implemented.

## 12. Policy Hardening Workflow (Dev → Stage → Prod)

```
        ┌──────────────────────────────┐
        │ TerraformExecutionRole-dev   │
        │                              │
        │ - Broad permissions          │
        │ - Fast iteration             │
        │ - Drift allowed              │
        └──────────────┬───────────────┘
                       │
                       │ 1. Real Terraform usage
                       ▼
        ┌──────────────────────────────┐
        │ AWS CloudTrail               │
        │                              │
        │ - Logs actual API calls      │
        └──────────────┬───────────────┘
                       │
                       │ 2. IAM Access Analyzer
                       ▼
        ┌──────────────────────────────┐
        │ Hardened IAM Policy (JSON)   │
        │                              │
        │ - Minimal permissions        │
        │ - No wildcards               │
        └──────────────┬───────────────┘
                       │
        ┌──────────────▼───────────────┐
        │ TerraformExecutionRole-stage │
        │                              │
        │ - Hardened policy            │
        │ - Clean apply from scratch   │
        └──────────────┬───────────────┘
                       │
        ┌──────────────▼───────────────┐
        │ TerraformExecutionRole-prod  │
        │                              │
        │ - Same policy as Stage       │
        │ - CI-only trust              │
        └──────────────────────────────┘
```

## 13. Where Policy Hardening Happens

**Short answer: In the Terraform management layer.**

```
IAM Identity Center
  └── users, groups, permission sets

Terraform Management Layer   ← permissions defined HERE
  └── TerraformExecutionRole-*
  └── trust & IAM policies
  └── S3/DynamoDB backends

Workload Terraform
  └── VPC, EKS, services
```

Rules:

- no manual IAM edits in Stage/Prod
- no ad-hoc fixes in Prod
- Stage and Prod policies must be identical

## 14. Terraform State & Safety

- Remote state in a centralized S3 bucket (Management)
- State locking via a centralized DynamoDB table (Management)
- Separate state keys per environment (dev/stage/prod/management)
- IAM policy scopes S3/DynamoDB access to per-environment key prefixes
- Bucket/table accessible only by TerraformExecutionRole-* (from workload accounts) and SSO roles from Management account
- Management account Terraform runs directly via SSO (no TerraformExecutionRole-management)
- No human access to state in workload accounts

Operational note:
- Existing states are migrated with ```terraform init -migrate-state``` per environment key.
- DynamoDB lock IDs match the state key, so key-prefix scoping applies to locks.

## 15. AssumeRole Flows (ASCII)

### Dev / Stage — Human via SSO

```
Developer
   ↓
IAM Identity Center (SSO)
   ↓
SSO-generated IAM Role
aws-reserved/sso.amazonaws.com/*
   ↓  sts:AssumeRole
TerraformExecutionRole-dev / stage
   ↓
AWS APIs
```

### Prod — CI/CD via GitHub OIDC

```
GitHub Actions
   ↓  OIDC token
GitHub OIDC Provider
   ↓  sts:AssumeRoleWithWebIdentity
TerraformExecutionRole-prod
   ↓
AWS APIs
```

## 16. What Is Explicitly Forbidden

- IAM users
- Access keys
- Humans deploying to Prod
- Manual IAM edits in Prod
- Different Stage / Prod policies

## 17. Summary

This IAM design provides:

- centralized identity management
- strict production isolation
- safe Terraform execution model
- CI-only production changes
- explicit Dev / Stage / Prod boundaries

It removes ambiguity around:
- who can deploy
- how Terraform authenticates
- why trust policies look unusual

## SMB-Friendly Note

For smaller teams, this repository uses a simplified IAM model:
- No dedicated TerraformAdminRole-*
- IAM changes are applied from the Management account via the
  member-account bootstrap role (default: ```OrganizationAccountAccessRole```)
- Execution roles in workload accounts do not have IAM write permissions

## Final Note

> This document exists so the code never has to explain itself.
> If something looks strict or unusual — it is intentional.
