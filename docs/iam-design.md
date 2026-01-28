# IAM Design 
## Terraform & CI/CD Execution Model

**Status**: Final / Production-ready blueprint
**Date**: January 2026
**Audience**: Platform Engineers
**Scope**: IAM, identity, Terraform execution, CI/CD
**Out of scope**: EKS workloads, application runtime IAM

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
| ** Management** | Identity & IAM control plane, Terraform management |
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


