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
      load_balancer_controller_role_arn = "arn:aws:iam::123456789012:role/TestController"
    }
  }
}

variables {
  demo_ingress_cidrs = ["203.0.113.10/32"]
}

run "demo_with_alb_and_hpa" {
  command = plan

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this["tc3-demo"].spec[0].behavior[0].scale_up[0].select_policy == "Max" && kubernetes_horizontal_pod_autoscaler_v2.this["tc3-demo"].spec[0].behavior[0].scale_down[0].select_policy == "Max"
    error_message = "As duas direções do HPA devem enviar selectPolicy válido à API Kubernetes."
  }

  assert {
    condition     = length(kubernetes_namespace_v1.this) == 2 && length(kubernetes_ingress_v1.demo) == 1
    error_message = "Deve haver dois namespaces e um Ingress na demonstração."
  }

  assert {
    condition     = kubernetes_ingress_v1.demo[0].spec[0].ingress_class_name == "alb" && kubernetes_ingress_v1.demo[0].metadata[0].annotations["alb.ingress.kubernetes.io/inbound-cidrs"] == "203.0.113.10/32"
    error_message = "O Ingress deve usar ALB e restringir acesso ao CIDR informado."
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this["tc3-demo"].spec[0].max_replicas == 5 && kubernetes_horizontal_pod_autoscaler_v2.this["tc3-demo"].spec[0].scale_target_ref[0].name == "tc3-demo"
    error_message = "HPA deve apontar para o Deployment de demonstração e limitar a cinco pods."
  }

  assert {
    condition     = kubernetes_deployment_v1.demo[0].spec[0].template[0].spec[0].container[0].resources[0].requests["cpu"] == "100m"
    error_message = "O exemplo precisa de requests.cpu para o HPA por utilização."
  }

  assert {
    condition     = kubernetes_service_account_v1.load_balancer_controller.metadata[0].annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::123456789012:role/TestController"
    error_message = "O controller deve receber a role IRSA exportada por infra/."
  }

  assert {
    condition     = !yamldecode(helm_release.load_balancer_controller.values[0]).controllerConfig.featureGates.ALBGatewayAPI && !yamldecode(helm_release.load_balancer_controller.values[0]).controllerConfig.featureGates.NLBGatewayAPI
    error_message = "O controller não deve depender de CRDs de Gateway API."
  }
}

run "demo_without_public_ingress" {
  command = plan

  variables {
    demo_ingress_cidrs = []
  }

  assert {
    condition     = length(kubernetes_ingress_v1.demo) == 0 && length(kubernetes_deployment_v1.demo) == 1 && length(kubernetes_service_v1.demo) == 1 && contains(keys(kubernetes_horizontal_pod_autoscaler_v2.this), "tc3-demo") && output.demo_url == null
    error_message = "CIDRs vazios devem manter aplicação e HPA, sem Ingress público ou URL."
  }
}

run "application_without_demo" {
  command = plan

  variables {
    enable_demo = false
    hpa_workloads = {
      api = {
        namespace       = "tech-challenge"
        deployment_name = "api"
        min_replicas    = 2
        max_replicas    = 8
        cpu_utilization = 70
      }
    }
  }

  assert {
    condition     = length(kubernetes_deployment_v1.demo) == 0 && length(kubernetes_ingress_v1.demo) == 0 && length(kubernetes_horizontal_pod_autoscaler_v2.this) == 1
    error_message = "Desabilitar o exemplo deve manter apenas o HPA da aplicação real."
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this["api"].spec[0].scale_target_ref[0].name == "api"
    error_message = "O HPA configurado deve apontar para o Deployment real."
  }
}

run "reject_unmanaged_hpa_namespace" {
  command = plan

  variables {
    hpa_workloads = { api = { namespace = "missing", deployment_name = "api" } }
  }

  expect_failures = [var.hpa_workloads]
}

run "reject_open_demo_ingress" {
  command = plan

  variables {
    demo_ingress_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.demo_ingress_cidrs]
}

run "production_without_demo" {
  command = plan

  variables {
    enable_demo          = false
    demo_ingress_cidrs   = []
    expected_environment = "hml"
  }

  assert {
    condition     = length(kubernetes_ingress_v1.demo) == 0
    error_message = "A plataforma sem demonstração não deve exigir CIDR de ALB."
  }

  assert {
    condition     = kubernetes_cluster_role_v1.terraform_plan.rule[0].verbs == tolist(["get", "list", "watch"])
    error_message = "A role Kubernetes de plan não deve permitir escrita."
  }
}

run "reject_wrong_infra_environment" {
  command = plan

  variables {
    expected_environment = "prod"
  }

  expect_failures = [data.terraform_remote_state.infra]
}
