variable "enable_datadog" {
  description = "Instala o Datadog Agent para TC3-10. Criar o Secret antes de habilitar."
  type        = bool
  default     = false
}

variable "datadog_site" {
  description = "Site da conta Datadog, por exemplo datadoghq.com (US1) ou datadoghq.eu (EU)."
  type        = string
  default     = "datadoghq.com"

  validation {
    condition     = contains(["datadoghq.com", "us3.datadoghq.com", "us5.datadoghq.com", "datadoghq.eu", "ap1.datadoghq.com", "ap2.datadoghq.com", "ddog-gov.com"], var.datadog_site)
    error_message = "Informe um site Datadog suportado, sem https://."
  }
}

variable "datadog_api_key_secret" {
  description = "Secret existente em observability, contendo a chave api-key. O valor nao entra no state."
  type        = string
  default     = "datadog-secret"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.datadog_api_key_secret))
    error_message = "Informe um nome DNS valido para o Secret."
  }
}

resource "helm_release" "datadog" {
  count      = var.enable_datadog ? 1 : 0
  name       = "datadog"
  repository = "https://helm.datadoghq.com"
  chart      = "datadog"
  version    = "3.245.0"
  namespace  = "observability"
  atomic     = true
  wait       = true
  timeout    = 1200

  values = [yamlencode({
    datadog = {
      apiKeyExistingSecret = var.datadog_api_key_secret
      site                 = var.datadog_site
      clusterName          = local.infra.cluster_name
      tags                 = ["env:${local.infra.environment}", "project:tech-challenge"]
      kubeStateMetricsCore = { enabled = true }
      logs = {
        enabled             = true
        containerCollectAll = false
      }
      otlp = {
        receiver = {
          protocols = {
            grpc = { enabled = true, endpoint = "0.0.0.0:4317", useHostPort = true }
          }
        }
      }
      apm = { socketEnabled = true }
    }
    clusterAgent = {
      enabled             = true
      admissionController = { enabled = false }
    }
  })]

  depends_on = [kubernetes_namespace_v1.this]

  lifecycle {
    precondition {
      condition     = contains(var.namespaces, "observability")
      error_message = "Inclua observability nos namespaces antes de instalar o Agent."
    }
  }
}
