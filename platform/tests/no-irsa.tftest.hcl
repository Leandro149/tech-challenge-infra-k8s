# Não executa aws eks get-token nem acessa um cluster real.
mock_provider "kubernetes" {}
mock_provider "helm" {}

override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = {
      aws_region             = "us-east-1"
      environment            = "hml"
      cluster_name           = "tech-challenge-dev"
      cluster_endpoint       = "https://test.eks.amazonaws.com"
      cluster_ca_certificate = "dGVzdC1jYQ=="
      vpc_id                 = "vpc-0123456789abcdef0"
    }
  }
}

variables {
  demo_ingress_cidrs = ["203.0.113.10/32"]
}

# Outputs nulos são omitidos pelo Terraform no state remoto.
run "controller_with_irsa_output_absent_from_state" {
  command = plan

  assert {
    condition     = try(kubernetes_service_account_v1.load_balancer_controller.metadata[0].annotations["eks.amazonaws.com/role-arn"], null) == null
    error_message = "Quando infra não exporta role IRSA, o service account não deve receber annotation de role."
  }
}
