# Esta etapa só deve ser aplicada depois de infra/ estar provisionada.
data "terraform_remote_state" "infra" {
  backend = var.infra_state_backend
  config  = var.infra_state_config

  lifecycle {
    postcondition {
      condition     = var.expected_environment == null || try(self.outputs.environment, null) == var.expected_environment
      error_message = "O state de infra não corresponde ao ambiente esperado. Confira bucket/key e aplique os outputs de infra."
    }
  }
}

locals {
  infra                             = data.terraform_remote_state.infra.outputs
  load_balancer_controller_role_arn = try(local.infra.load_balancer_controller_role_arn, null)
  token_args = [
    "eks", "get-token",
    "--region", local.infra.aws_region,
    "--cluster-name", local.infra.cluster_name,
  ]
}

provider "kubernetes" {
  host                   = local.infra.cluster_endpoint
  cluster_ca_certificate = base64decode(local.infra.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.token_args
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.infra.cluster_endpoint
    cluster_ca_certificate = base64decode(local.infra.cluster_ca_certificate)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.token_args
    }
  }
}
