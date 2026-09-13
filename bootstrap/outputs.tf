output "github_environment_variables" {
  description = "Variáveis não secretas para configurar os GitHub Environments."
  value = {
    for name, suffix in local.environments : name => {
      AWS_PLAN_ROLE_ARN = aws_iam_role.terraform["${name}-plan"].arn
      AWS_ROLE_ARN      = aws_iam_role.terraform["${name}-apply"].arn
      TF_STATE_BUCKET   = local.state_bucket_names[name]
    }
  }
}
