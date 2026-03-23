# VPC Module
# Creates a VPC with tiered subnet design using simple CIDR allocation
# - Public subnets (/24): NAT Gateways, ALBs
# - Isolated subnets (/24): Kafka, RDS (no internet access)
# - Private subnets (/22): EKS nodes and pods
#
# CIDR Allocation Strategy (using third octet as marker):
# VPC: /16 (e.g., 10.0.0.0/16 for dev, 10.1.0.0/16 for stage, 10.2.0.0/16 for prod)
# Public: 10.X.1.0/24, 10.X.2.0/24, 10.X.3.0/24 (one per AZ)
# Isolated: 10.X.10.0/24, 10.X.11.0/24, 10.X.12.0/24 (one per AZ)
# Private: 10.X.20.0/22, 10.X.24.0/22, 10.X.28.0/22 (one per AZ)
#
# Benefits:
# - Simple: no complex bit calculations, easy to read and remember
# - Clear: third octet shows subnet type (1-3=public, 10-12=isolated, 20+=private)
# - Safe: large gaps between subnet types prevent overlap
# - Scalable: /16 provides 65,536 addresses for all environments

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Get availability zones for the region
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
# Recommended: /16 for all environments (65,536 addresses)
# Simple and scalable - no need to worry about IP exhaustion
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  
  # DNS Support: Enables DNS resolution for instances in VPC
  # - Required for Route53 private hosted zones
  # - Required for EKS service discovery
  # - Required for RDS endpoint resolution
  # - Without this, instances can't resolve DNS names
  enable_dns_support = true
  
  # DNS Hostnames: Assigns DNS hostnames to instances (e.g., ip-10-0-1-5.ec2.internal)
  # - Required for EKS (Kubernetes needs DNS hostnames)
  # - Required for some AWS services (RDS, ElastiCache)
  # - Makes instances accessible by hostname within VPC
  # - Requires enable_dns_support = true (enabled above)
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-vpc"
    }
  )
}

# Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-igw"
    }
  )
}

# Simplified CIDR allocation using third octet as marker
# VPC: /16 (e.g., 10.0.0.0/16 for dev, 10.1.0.0/16 for stage, 10.2.0.0/16 for prod)
# Public: 10.X.1.0/24, 10.X.2.0/24, 10.X.3.0/24 (one per AZ)
# Isolated: 10.X.10.0/24, 10.X.11.0/24, 10.X.12.0/24 (one per AZ)
# Private: 10.X.20.0/22, 10.X.24.0/22, 10.X.28.0/22 (one per AZ, /22 for EKS pods)
#
# Benefits:
# - Easy to read: third octet shows subnet type (1-3=public, 10-12=isolated, 20+=private)
# - No overlap: large gaps between subnet types prevent mistakes
# - Simple: no complex bit calculations needed, easy to remember
locals {
  # CIDR calculation constants
  # For /24 subnets from /16 VPC: newbits = 8 (24 - 16)
  # For /22 subnets from /16 VPC: newbits = 6 (22 - 16)
  public_subnet_newbits    = 8   # Creates /24 subnets (256 addresses each)
  isolated_subnet_newbits  = 8   # Creates /24 subnets (256 addresses each)
  private_subnet_newbits   = 6   # Creates /22 subnets (1024 addresses each)
  
  # Extract AZ suffix (last letter) for resource naming
  # Example: "eu-central-1a" → "a", "eu-central-1b" → "b"
  # Used in resource names: dev-public-a, dev-public-b, etc.
  az_suffix = [for az in var.availability_zones : substr(az, -1, 1)]
  
  # NAT Gateway configuration
  # Calculate how many NAT Gateways to create based on single_nat_gateway flag
  # single_nat_gateway=true: 1 NAT Gateway (cost-optimized for dev, ~$32/month)
  # single_nat_gateway=false: 1 NAT Gateway per AZ (high availability for prod, ~$97/month for 3 AZs)
  nat_gateway_count = var.single_nat_gateway ? 1 : length(var.availability_zones)
  # Map AZ index -> NAT index.
  # Single NAT mode: all private route tables point to NAT[0].
  # Multi NAT mode: each AZ points to NAT with the same index.
  nat_index_by_az = {
    for idx, _az in var.availability_zones :
    idx => (var.single_nat_gateway ? 0 : idx)
  }
  
  # Subnet index offsets (third octet markers)
  
  # Public: start at index 1 → 10.X.1.0/24, 10.X.2.0/24, 10.X.3.0/24
  public_subnet_start_index    = 1
  # Isolated: start at index 10 → 10.X.10.0/24, 10.X.11.0/24, 10.X.12.0/24
  isolated_subnet_start_index   = 10
  # Private: start at index 5 → 10.X.20.0/22, 10.X.24.0/22, 10.X.28.0/22
  # Why index 5? We start with VPC /16 (10.0.0.0/16)
  # cidrsubnet("10.0.0.0/16", 6, N) means:
  #   - Start with: 10.0.0.0/16 (VPC CIDR)
  #   - newbits=6: add 6 bits to mask → /16 + 6 = /22
  #   - This creates 2^6 = 64 blocks, each block is /22 (1024 addresses)
  #   - Index N selects one of these 64 blocks
  # Examples (testing in terraform console: cidrsubnet("10.0.0.0/16", 6, N)):
  #   - index 0 → 10.0.0.0/22   (10.0.0.0 - 10.0.3.255)   [! overlaps with Public 1-3]
  #   - index 1 → 10.0.4.0/22   (10.0.4.0 - 10.0.7.255)   [ free, but doesn't start at 20]
  #   - index 2 → 10.0.8.0/22   (10.0.8.0 - 10.0.11.255)  [! overlaps with Isolated 10-11]
  #   - index 3 → 10.0.12.0/22  (10.0.12.0 - 10.0.15.255) [! overlaps with Isolated 12]
  #   - index 4 → 10.0.16.0/22  (10.0.16.0 - 10.0.19.255) [ free, but doesn't start at 20]
  #   - index 5 → 10.0.20.0/22  (10.0.20.0 - 10.0.23.255) [ ok - free AND starts at 20!]
  #   - index 6 → 10.0.24.0/22  (10.0.24.0 - 10.0.27.255) [ free]
  #   - index 7 → 10.0.28.0/22  (10.0.28.0 - 10.0.31.255) [ free]
  # Index 5 is the minimum safe index that avoids overlap and matches our naming convention.
  private_subnet_start_index   = 5
}

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  # Public subnets: 10.X.1.0/24, 10.X.2.0/24, 10.X.3.0/24
  # Example for 10.0.0.0/16:
  #   - count.index=0: cidrsubnet("10.0.0.0/16", 8, 1) → 10.0.1.0/24
  #   - count.index=1: cidrsubnet("10.0.0.0/16", 8, 2) → 10.0.2.0/24
  #   - count.index=2: cidrsubnet("10.0.0.0/16", 8, 3) → 10.0.3.0/24
  cidr_block              = cidrsubnet(var.vpc_cidr, local.public_subnet_newbits, local.public_subnet_start_index + count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      # Extract last character from AZ name (e.g., "eu-central-1a" → "a")
      # Result: dev-public-a, dev-public-b, dev-public-c
      Name = "${var.vpc_name}-public-${local.az_suffix[count.index]}"
      Type = "public"
      Tier = "public"
    }
  )
}

# Isolated Subnets (data tier - no internet access)
# Size: /24 (256 addresses per subnet)
# Purpose: Kafka (MSK), RDS, ElastiCache - data workloads that should NOT have internet access
# CIDR allocation: 10.X.10.0/24, 10.X.11.0/24, 10.X.12.0/24 (one per AZ)
#   - Dev: 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24
#   - Stage: 10.1.10.0/24, 10.1.11.0/24, 10.1.12.0/24
#   - Prod: 10.2.10.0/24, 10.2.11.0/24, 10.2.12.0/24
# Security: No route to Internet Gateway or NAT Gateway (truly isolated)
# Multi-AZ requirement:
#   - Kafka (MSK): Requires 3 AZs minimum for multi-AZ deployment
#   - RDS: Can use multi-AZ for high availability
#   - ElastiCache: Can use multi-AZ replication
resource "aws_subnet" "isolated" {
  count = length(var.availability_zones)  # One subnet per AZ for multi-AZ data stores (Kafka, RDS, ElastiCache)

  vpc_id            = aws_vpc.this.id
  # Isolated subnets: 10.X.10.0/24, 10.X.11.0/24, 10.X.12.0/24
  # Example for 10.0.0.0/16:
  #   - count.index=0: cidrsubnet("10.0.0.0/16", 8, 10) → 10.0.10.0/24
  #   - count.index=1: cidrsubnet("10.0.0.0/16", 8, 11) → 10.0.11.0/24
  #   - count.index=2: cidrsubnet("10.0.0.0/16", 8, 12) → 10.0.12.0/24
  cidr_block        = cidrsubnet(var.vpc_cidr, local.isolated_subnet_newbits, local.isolated_subnet_start_index + count.index)
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.tags,
    {
      # Extract last character from AZ name (e.g., "eu-central-1a" → "a")
      # Result: dev-isolated-a, dev-isolated-b, dev-isolated-c
      Name = "${var.vpc_name}-isolated-${local.az_suffix[count.index]}"
      Type = "isolated"
      Tier = "data"
    }
  )
}

# Private Subnets (one per AZ)
# Size: /22 (1,024 addresses per subnet)
# Purpose: EKS nodes and pods, application workloads
# CIDR allocation: 10.X.20.0/22, 10.X.24.0/22, 10.X.28.0/22 (one per AZ)
#   - Dev: 10.0.20.0/22, 10.0.24.0/22, 10.0.28.0/22
#   - Stage: 10.1.20.0/22, 10.1.24.0/22, 10.1.28.0/22
#   - Prod: 10.2.20.0/22, 10.2.24.0/22, 10.2.28.0/22
# Larger than public/isolated because EKS pods consume many IPs (one per pod)
# Uses cidrsubnet() to properly calculate /22 boundaries from /16 VPC
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.this.id
  # Private subnets: 10.X.20.0/22, 10.X.24.0/22, 10.X.28.0/22 (one per AZ, /22 for EKS pods)
  # Using /22 (1024 addresses) for EKS pods which need many IPs
  # Example for 10.0.0.0/16:
  #   - count.index=0: cidrsubnet("10.0.0.0/16", 6, 5) → 10.0.20.0/22 (10.0.20.0 - 10.0.23.255)
  #   - count.index=1: cidrsubnet("10.0.0.0/16", 6, 6) → 10.0.24.0/22 (10.0.24.0 - 10.0.27.255)
  #   - count.index=2: cidrsubnet("10.0.0.0/16", 6, 7) → 10.0.28.0/22 (10.0.28.0 - 10.0.31.255)
  cidr_block        = cidrsubnet(var.vpc_cidr, local.private_subnet_newbits, local.private_subnet_start_index + count.index)
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.tags,
    {
      # Extract last character from AZ name (e.g., "eu-central-1a" → "a")
      # Result: dev-private-a, dev-private-b, dev-private-c
      Name = "${var.vpc_name}-private-${local.az_suffix[count.index]}"
      Type = "private"
      Tier = "application"
    }
  )
}

# Note: Kafka/RDS go in isolated subnets (created above)
# No separate "kafka" subnets - they use the isolated tier

# Elastic IPs for NAT Gateways
# NAT Gateway is always created for private subnets (required for outbound internet access)
# If single_nat_gateway=true: create 1 EIP (cost-optimized for dev)
# If single_nat_gateway=false: create 1 EIP per AZ (high availability for prod)
resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(
    var.tags,
    {
      # Extract last character from AZ name (e.g., "eu-central-1a" → "a")
      # Result: dev-nat-eip-a (single NAT in first AZ) or dev-nat-eip-a, dev-nat-eip-b, dev-nat-eip-c (multi-AZ)
      # When single_nat_gateway=true, count=1 so count.index=0 → uses first AZ suffix
      Name = "${var.vpc_name}-nat-eip-${local.az_suffix[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}

# NAT Gateways
# If single_nat_gateway=true: create 1 NAT in first AZ (~$32/month for dev)
# If single_nat_gateway=false: create 1 NAT per AZ (~$97/month for prod, high availability)
resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id

  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    var.tags,
    {
      # Extract last character from AZ name (e.g., "eu-central-1a" → "a")
      # Result: dev-nat-a (single NAT in first AZ) or dev-nat-a, dev-nat-b, dev-nat-c (multi-AZ)
      # When single_nat_gateway=true, count=1 so count.index=0 → uses first AZ suffix
      Name = "${var.vpc_name}-nat-${local.az_suffix[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-public-rt"
    }
  )
}

# Route Table Associations for Public Subnets
resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Tables for Private Subnets (one per AZ)
resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[local.nat_index_by_az[count.index]].id
  }

  tags = merge(
    var.tags,
    {
      # Extract last character from AZ name (e.g., "eu-central-1a" → "a")
      # Result: dev-private-rt-a, dev-private-rt-b, dev-private-rt-c
      Name = "${var.vpc_name}-private-rt-${local.az_suffix[count.index]}"
    }
  )
}

# Route Table Associations for Private Subnets
resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Route Tables for Isolated Subnets (one per AZ)
# IMPORTANT: Isolated subnets have NO internet routes (truly isolated)
# No route to Internet Gateway or NAT Gateway
# Only local VPC routes (for communication with private subnets)
resource "aws_route_table" "isolated" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id

  # No routes to internet - isolated subnets are truly isolated
  # Only local VPC communication is allowed

  tags = merge(
    var.tags,
    {
      # Extract last character from AZ name (e.g., "eu-central-1a" → "a")
      # Result: dev-isolated-rt-a, dev-isolated-rt-b, dev-isolated-rt-c
      Name = "${var.vpc_name}-isolated-rt-${local.az_suffix[count.index]}"
    }
  )
}

# Route Table Associations for Isolated Subnets
resource "aws_route_table_association" "isolated" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated[count.index].id
}
