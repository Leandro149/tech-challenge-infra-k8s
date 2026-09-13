provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
  default_tags {
    tags = { Project = var.project_name, ManagedBy = "Terraform", Component = "ci-bootstrap" }
  }
}

locals {
  environments = { homologacao = "hml", producao = "prod" }
  roles = merge(
    { for name, suffix in local.environments : "${name}-plan" => { environment = name, suffix = suffix, mode = "plan", github_environment = "${name}-plan" } },
    { for name, suffix in local.environments : "${name}-apply" => { environment = name, suffix = suffix, mode = "apply", github_environment = name } },
  )
  github_oidc_arn = var.existing_github_oidc_provider_arn != null ? var.existing_github_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_github_oidc_provider_arn == null ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_s3_bucket" "state" {
  for_each = local.environments
  bucket   = "${var.project_name}-tfstate-${var.aws_account_id}-${each.value}"
  tags     = { Environment = each.value }
}

resource "aws_s3_bucket_versioning" "state" {
  for_each = aws_s3_bucket.state
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  for_each = aws_s3_bucket.state
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  for_each                = aws_s3_bucket.state
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state" {
  for_each = aws_s3_bucket.state
  bucket   = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "RequireTLS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [each.value.arn, "${each.value.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_iam_role" "terraform" {
  for_each             = local.roles
  name                 = "${var.project_name}-${each.value.suffix}-terraform-${each.value.mode}"
  max_session_duration = 7200
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.github_oidc_arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:${each.value.github_environment}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "state" {
  for_each = local.roles
  name     = "environment-state"
  role     = aws_iam_role.terraform[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.state[each.value.environment].arn
      },
      {
        Effect   = "Allow"
        Action   = each.value.mode == "apply" ? ["s3:GetObject", "s3:PutObject"] : ["s3:GetObject"]
        Resource = [for root in ["infra", "platform"] : "${aws_s3_bucket.state[each.value.environment].arn}/${root}/terraform.tfstate"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [for root in ["infra", "platform"] : "${aws_s3_bucket.state[each.value.environment].arn}/${root}/terraform.tfstate.tflock"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "discovery" {
  for_each = local.roles
  name     = "terraform-discovery"
  role     = aws_iam_role.terraform[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:GetCallerIdentity", "ec2:Describe*", "eks:Describe*", "eks:List*", "iam:Get*", "iam:List*", "logs:DescribeLogGroups", "logs:ListTagsForResource", "logs:ListTagsLogGroup"]
      Resource = "*"
    }]
  })
}
