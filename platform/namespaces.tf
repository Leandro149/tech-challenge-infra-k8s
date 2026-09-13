resource "kubernetes_namespace_v1" "this" {
  for_each = var.namespaces

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/part-of"    = "tech-challenge"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}
