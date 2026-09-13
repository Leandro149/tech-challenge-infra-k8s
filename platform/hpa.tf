locals {
  hpa_workloads = merge(var.hpa_workloads, var.enable_demo ? {
    tc3-demo = {
      namespace       = var.demo_namespace
      deployment_name = "tc3-demo"
      min_replicas    = 2
      max_replicas    = 5
      cpu_utilization = 50
    }
  } : {})
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  for_each = local.hpa_workloads

  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.this[each.value.namespace].metadata[0].name
  }

  spec {
    min_replicas = each.value.min_replicas
    max_replicas = each.value.max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = each.value.deployment_name
    }

    metric {
      type = "Resource"

      resource {
        name = "cpu"

        target {
          type                = "Utilization"
          average_utilization = each.value.cpu_utilization
        }
      }
    }

    behavior {
      scale_down {
        stabilization_window_seconds = 300

        policy {
          type           = "Percent"
          value          = 50
          period_seconds = 60
        }
      }

      scale_up {
        stabilization_window_seconds = 0

        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 60
        }
      }
    }
  }

  depends_on = [helm_release.metrics_server, kubernetes_deployment_v1.demo]
}
