variable "vpc_name" {
  description = "Name prefix for VPC resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (recommended: /16 for all environments)"
  type        = string
  default     = "10.0.0.0/16"  # /16 for all environments - simple and scalable
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway for all AZs (cost-optimized for dev) or one per AZ (high availability for prod). NAT Gateway is always created for private subnets."
  type        = bool
  default     = false  # false = one per AZ (HA), true = single NAT (cost-optimized)
}

variable "enable_vpn_gateway" {
  description = "Enable VPN Gateway (optional)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
