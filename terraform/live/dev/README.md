# Dev Environment Infrastructure

This directory contains infrastructure for the **dev** environment.

## What's Included

- **VPC**: Public, private, and isolated subnets across 3 AZs
- NAT Gateways for private subnet internet access
- Internet Gateway for public subnets

## Setup

### 1. Configure AWS Profile with Assume Role

Use a profile that assumes `TerraformExecutionRole-dev` in the dev account:

```ini
# Step 1: SSO profile for initial authentication in dev account
[profile dev-engineer]
sso_start_url = https://your-sso-portal.awsapps.com/start
sso_region = eu-central-1
sso_account_id = <DEV-ACCOUNT-ID>
sso_role_name = <SSO-PERMISSION-SET-NAME>
region = eu-central-1

# Step 2: Profile that assumes TerraformExecutionRole-dev
[profile dev-terraform]
source_profile = dev-engineer
role_arn = arn:aws:iam::<DEV-ACCOUNT-ID>:role/TerraformExecutionRole-dev
region = eu-central-1
```

**Important:**
- The `dev-terraform` profile automatically assumes `TerraformExecutionRole-dev` when used
- Terraform provider uses this role for infrastructure changes in dev account

### 2. Configure Backend

```bash
cp backend.hcl.example backend.hcl
```

Edit `backend.hcl` and replace:
- `<MANAGEMENT-ACCOUNT-ID>` with your Management account ID

`backend.hcl` also contains:

```hcl
assume_role = {
  role_arn     = "arn:aws:iam::<MANAGEMENT-ACCOUNT-ID>:role/TerraformStateAccessRole-dev"
  session_name = "terraform-backend-dev"
}
```

This makes backend calls (S3 + DynamoDB lock) run through a dedicated Management role with access only to `dev/*`.

### 3. Initialize and Apply

```bash
# Step 1: Login via SSO to dev account
aws sso login --profile dev-engineer --no-browser

# Step 2: Export the terraform profile (which assumes TerraformExecutionRole-dev)
export AWS_PROFILE=dev-terraform

# Step 3: Initialize Terraform
# Backend will assume TerraformStateAccessRole-dev in Management account
terraform init -reconfigure -backend-config=backend.hcl

# Step 4: Plan and Apply
# Provider assumes TerraformExecutionRole-dev (configured in providers.tf)
terraform plan
terraform apply
```

### How It Works

1. **SSO Authentication**: `dev-engineer` profile authenticates via SSO
2. **Assume Role**: `dev-terraform` profile automatically assumes `TerraformExecutionRole-dev`
3. **Execution Role Permission**: `TerraformExecutionRole-dev` is allowed to call `sts:AssumeRole` only for `TerraformStateAccessRole-dev`
4. **Backend Access**: Terraform backend additionally assumes `TerraformStateAccessRole-dev` in Management account
5. **Resource Management**: Provider uses `TerraformExecutionRole-dev` for dev resources (configured in `providers.tf`)

**Security Model:**
- Dev engineers do not need broad Management permissions
- Backend access is isolated to `dev/*` via `TerraformStateAccessRole-dev`
- Resource creation in dev account is isolated via `TerraformExecutionRole-dev`

## VPC Structure

- **Public Subnets**: 3 subnets (one per AZ) for load balancers, NAT gateways
- **Private Subnets**: 3 subnets (one per AZ) for EKS nodes, application workloads
- **Isolated Subnets**: 3 subnets (one per AZ) for Kafka (MSK), RDS, ElastiCache (no internet access)

All subnets are in separate CIDR blocks for isolation. Isolated subnets span all AZs for multi-AZ deployment support.
