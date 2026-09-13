mock_provider "aws" {
  override_during = plan
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::test-state" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::213284176265:oidc-provider/token.actions.githubusercontent.com" }
  }
}

run "separate_environments_and_roles" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state["homologacao"].bucket != aws_s3_bucket.state["producao"].bucket && length(aws_iam_role.terraform) == 4
    error_message = "Os ambientes devem ter buckets separados e roles distintas de plan/apply."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state["producao"].versioning_configuration[0].status == "Enabled" && aws_s3_bucket_public_access_block.state["producao"].block_public_policy
    error_message = "O state deve ser privado e versionado."
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
