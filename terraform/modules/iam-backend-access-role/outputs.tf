output "role_names" {
  description = "Map of environment to backend access role name in management account."
  value = {
    for env, role in aws_iam_role.this :
    env => role.name
  }
}

output "role_arn_patterns" {
  description = "IAM role ARN patterns for backend access roles."
  value = [
    for env, role in aws_iam_role.this :
    role.arn
  ]
}

output "assumed_role_arn_patterns" {
  description = "STS assumed-role ARN patterns for backend access roles."
  value = [
    for env, role in aws_iam_role.this :
    "arn:aws:sts::${var.management_account_id}:assumed-role/${role.name}/*"
  ]
}
