variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Project name used for resource naming"
  type        = string
  default     = "autoscaling-eks"
}

variable "environments" {
  description = "Target environments"
  type        = list(string)
  default     = ["dev", "stage", "prod"]
}
