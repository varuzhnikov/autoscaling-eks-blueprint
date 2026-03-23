# VPC for Dev Environment
# Creates VPC with tiered subnet design using simple CIDR allocation
# - Public subnets (/24): NAT Gateways, ALBs
# - Isolated subnets (/24): Kafka, RDS (no internet access)
# - Private subnets (/22): EKS nodes and pods
#
# CIDR Allocation (third octet as marker):
# Public: 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24
# Isolated: 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24
# Private: 10.0.20.0/22, 10.0.24.0/22, 10.0.28.0/22

module "vpc" {
  source = "../../modules/vpc"

  vpc_name = "dev"
  vpc_cidr = "10.0.0.0/16"  # /16 for dev (65,536 addresses) - simple and scalable

  # Use 3 availability zones
  availability_zones = [
    "${var.aws_region}a",
    "${var.aws_region}b",
    "${var.aws_region}c"
  ]

  # NAT Gateway is always created for private subnets (required for outbound internet access)
  # Use single NAT Gateway (cost-optimized for dev: ~$32/month instead of ~$97/month)
  # For prod: set single_nat_gateway = false for high availability (one NAT per AZ)
  single_nat_gateway = true

  tags = {
    Environment = "dev"
    Project     = var.project
    ManagedBy   = "terraform"
  }
}
