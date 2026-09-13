resource "kubernetes_deployment_v1" "demo" {
  count = var.enable_demo ? 1 : 0

  metadata {
    name      = "tc3-demo"
    namespace = kubernetes_namespace_v1.this[var.demo_namespace].metadata[0].name
    labels    = { app = "tc3-demo" }
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "tc3-demo" }
    }

    template {
      metadata {
        labels = { app = "tc3-demo" }
      }

      spec {
        automount_service_account_token = false

        container {
          name  = "web"
          image = var.demo_image

          port {
            container_port = 80
          }

          resources {
            requests = { cpu = "100m", memory = "64Mi" }
            limits   = { cpu = "500m", memory = "128Mi" }
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 15
            period_seconds        = 20
            timeout_seconds       = 5
          }
        }
      }
    }
  }

  # HPA passa a controlar o número de réplicas após o primeiro apply.
  lifecycle {
    ignore_changes = [spec[0].replicas]
  }
}

resource "kubernetes_service_v1" "demo" {
  count = var.enable_demo ? 1 : 0

  metadata {
    name      = "tc3-demo"
    namespace = kubernetes_namespace_v1.this[var.demo_namespace].metadata[0].name
  }

  spec {
    selector = { app = "tc3-demo" }
    type     = "ClusterIP"

    port {
      port        = 80
      target_port = 80
    }
  }

  depends_on = [helm_release.load_balancer_controller]
}

resource "kubernetes_ingress_v1" "demo" {
  count = var.enable_demo ? 1 : 0

  wait_for_load_balancer = true

  metadata {
    name      = "tc3-demo"
    namespace = kubernetes_namespace_v1.this[var.demo_namespace].metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = 80 }])
      "alb.ingress.kubernetes.io/healthcheck-path" = "/"
      "alb.ingress.kubernetes.io/inbound-cidrs"    = join(",", var.demo_ingress_cidrs)
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.demo[0].metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  timeouts {
    create = "15m"
    delete = "15m"
  }

  depends_on = [helm_release.load_balancer_controller, kubernetes_deployment_v1.demo]
}
