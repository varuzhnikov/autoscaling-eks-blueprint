locals {
  role_names = {
    for env in keys(var.env_accounts) :
    env => "TerraformStateAccessRole-${env}"
  }
}

data "aws_iam_policy_document" "trust" {
  for_each = var.env_accounts

  statement {
    sid    = "AllowEnvTerraformExecutionRole"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:sts::${each.value}:assumed-role/TerraformExecutionRole-${each.key}/*",
        "arn:aws:iam::${each.value}:role/TerraformExecutionRole-${each.key}"
      ]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.env_accounts

  name               = local.role_names[each.key]
  assume_role_policy = data.aws_iam_policy_document.trust[each.key].json

  tags = {
    Purpose = "terraform-backend-access"
    Env     = each.key
  }
}

data "aws_iam_policy_document" "permissions" {
  for_each = var.env_accounts

  statement {
    sid    = "TerraformStateList"
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      var.state_bucket_arn
    ]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${each.key}/*"]
    }
  }

  statement {
    sid    = "TerraformStateObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${var.state_bucket_arn}/${each.key}/*"
    ]
  }

  statement {
    sid    = "TerraformStateLocking"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem"
    ]
    resources = [
      var.lock_table_arn
    ]
    condition {
      test     = "StringLike"
      variable = "dynamodb:LeadingKeys"
      values   = ["${each.key}/*"]
    }
  }
}

resource "aws_iam_policy" "this" {
  for_each = var.env_accounts

  name   = "${local.role_names[each.key]}-policy"
  policy = data.aws_iam_policy_document.permissions[each.key].json
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = var.env_accounts

  role       = aws_iam_role.this[each.key].name
  policy_arn = aws_iam_policy.this[each.key].arn
}
