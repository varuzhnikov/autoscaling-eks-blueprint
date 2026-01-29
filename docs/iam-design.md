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

Terraform flow:

1. authenticate via SSO or CI
1. assume TerraformExecutionRole
1. talk to AWS APIs

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

### 9.2 Prod — CI/CD Only (GitHub OIDC)

TODO

## 10. Permissions Model

### Key Rule

> **Trust defines _who can assume._**
> **IAM policy defines _what can be done._**

TerraformExecutionRole policy controls:
- allowed AWS services
- allowed regions
- resource scope

## 11. Environment Strategy

| **Environment** | **Human Writes** | **Terraform Permissions** |
| :--- | :--- | :--- |
| Dev | Allowed | Broad |
| Stage | No | Hardened |
| Prod | No | Hardened (CI-only) |

Dev may drift.
Stage & Prod must not.

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

- Remote state in S3
- State locking via DynamoDB
- One backend per environment
- Buckets accessible only by TerraformExecutionRole
- No human access to state

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

## Final Note

> This document exists so the code never has to explain itself.
> If something looks strict or unusual — it is intentional.
