# Não executa aws eks get-token nem acessa um cluster real.
mock_provider "kubernetes" {}
mock_provider "helm" {}

override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = {
      aws_region                        = "us-east-1"
      environment                       = "hml"
      cluster_name                      = "tech-challenge-dev"
      cluster_endpoint                  = "https://test.eks.amazonaws.com"
      cluster_ca_certificate            = "dGVzdC1jYQ=="
      vpc_id                            = "vpc-0123456789abcdef0"
      load_balancer_controller_role_arn = null
    }
  }
}

variables {
  demo_ingress_cidrs = ["203.0.113.10/32"]
}

run "controller_without_irsa_annotation" {
  command = plan

  assert {
    condition     = try(kubernetes_service_account_v1.load_balancer_controller.metadata[0].annotations["eks.amazonaws.com/role-arn"], null) == null
    error_message = "Quando infra não exporta role IRSA, o service account não deve receber annotation de role."
  }
}
