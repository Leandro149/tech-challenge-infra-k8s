output "github_environment_variables" {
  description = "Variáveis não secretas para configurar os GitHub Environments."
  value = {
    for name, suffix in local.environments : name => {
      AWS_PLAN_ROLE_ARN = var.manage_github_oidc_roles ? aws_iam_role.terraform["${name}-plan"].arn : "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${suffix}-terraform-plan"
      AWS_ROLE_ARN      = var.manage_github_oidc_roles ? aws_iam_role.terraform["${name}-apply"].arn : "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${suffix}-terraform-apply"
      TF_STATE_BUCKET   = local.state_bucket_names[name]
    }
  }
}
