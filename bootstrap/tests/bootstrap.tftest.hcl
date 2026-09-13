mock_provider "aws" {
  override_during = plan
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::213284176265:oidc-provider/token.actions.githubusercontent.com" }
  }
}

run "separate_environments_and_roles" {
  command = plan

  assert {
    condition     = local.state_bucket_names["homologacao"] != local.state_bucket_names["producao"] && length(aws_iam_role.terraform) == 4
    error_message = "Os ambientes devem ter buckets separados e roles distintas de plan/apply."
  }

  assert {
    condition     = local.state_bucket_names["producao"] == "tech-challenge-tfstate-213284176265-prod"
    error_message = "O nome do bucket de produção deve continuar estável."
  }

  assert {
    condition     = jsondecode(aws_iam_role.terraform["producao-apply"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:Leandro149/tech-challenge-infra-k8s:environment:producao"
    error_message = "A role de produção deve confiar somente no Environment correto do repositório."
  }

  assert {
    condition     = tolist(jsondecode(aws_iam_role_policy.state["homologacao-plan"].policy).Statement[1].Action) == tolist(["s3:GetObject"])
    error_message = "Plan não deve gravar o state."
  }

  assert {
    condition     = !contains(local.application_roles["producao-apply"], "arn:aws:iam::213284176265:role/tech-challenge-prod-terraform-apply")
    error_message = "A pipeline não deve ter permissão IAM de alterar sua própria role de execução."
  }

  assert {
    condition     = aws_iam_role.terraform["producao-apply"].max_session_duration == 7200 && length(aws_iam_role_policy.apply) == 2
    error_message = "Sessões devem cobrir o deploy e somente roles de apply recebem provisioning."
  }
}

run "reuse_existing_github_provider" {
  command = plan

  variables {
    existing_github_oidc_provider_arn = "arn:aws:iam::213284176265:oidc-provider/token.actions.githubusercontent.com"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "Um provider existente deve ser reutilizado."
  }
}
