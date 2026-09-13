provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
  default_tags {
    tags = { Project = var.project_name, ManagedBy = "Terraform", Component = "ci-bootstrap" }
  }
}

locals {
  environments       = { homologacao = "hml", producao = "prod" }
  state_bucket_names = { for name, suffix in local.environments : name => "${var.project_name}-tfstate-${var.aws_account_id}-${suffix}" }
  state_bucket_arns  = { for name, bucket in local.state_bucket_names : name => "arn:aws:s3:::${bucket}" }
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
        Resource = local.state_bucket_arns[each.value.environment]
      },
      {
        Effect   = "Allow"
        Action   = each.value.mode == "apply" ? ["s3:GetObject", "s3:PutObject"] : ["s3:GetObject"]
        Resource = [for root in ["infra", "platform"] : "${local.state_bucket_arns[each.value.environment]}/${root}/terraform.tfstate"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [for root in ["infra", "platform"] : "${local.state_bucket_arns[each.value.environment]}/${root}/terraform.tfstate.tflock"]
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
