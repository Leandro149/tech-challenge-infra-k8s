# Helm guarda releases em secrets; plan precisa ler esses objetos, sem alterá-los.
resource "kubernetes_cluster_role_v1" "terraform_plan" {
  metadata {
    name = "terraform-plan"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    non_resource_urls = ["*"]
    verbs             = ["get"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "terraform_plan" {
  metadata {
    name = "terraform-plan"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.terraform_plan.metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = "terraform-plan"
  }
}
