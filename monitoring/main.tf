terraform {
  required_version = ">= 1.13.0, < 2.0.0"
  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 4.21.0"
    }
  }
}

# DD_API_KEY e DD_APP_KEY sao lidas pelo provider, fora dos arquivos de configuracao.
provider "datadog" {
  api_url = var.datadog_api_url
}

variable "datadog_api_url" {
  type        = string
  description = "API correspondente ao site da conta Datadog."
  default     = "https://api.datadoghq.com/"
}

variable "environment" {
  type    = string
  default = "prod"
  validation {
    condition     = contains(["prod", "hml"], var.environment)
    error_message = "Use prod ou hml, igual a DD_ENV e aos labels da API."
  }
}

variable "cluster_name" {
  type        = string
  description = "Nome exato do cluster EKS monitorado."
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]*$", var.cluster_name))
    error_message = "Informe o nome do cluster EKS."
  }
}

variable "notification_recipients" {
  type        = string
  description = "Mencoes Datadog para notificacao, por exemplo @email. Vazio cria alertas somente na interface."
  default     = ""
}

locals {
  service = "tech-challenge-api"
  scope   = "service:${local.service},env:${var.environment}"
  cluster = "kube_cluster_name:${var.cluster_name}"
  tags    = ["service:${local.service}", "env:${var.environment}", "project:tech-challenge", "task:tc3-10"]
  metric_monitors = {
    cpu = {
      name      = "CPU de usuario dos nodes acima de 80%"
      query     = "avg(last_5m):avg:system.cpu.user{${local.cluster}} by {host} > 80"
      threshold = 80
      no_data   = false
    }
    memory = {
      name      = "Memoria disponivel dos nodes abaixo de 15%"
      query     = "avg(last_5m):avg:system.mem.pct_usable{${local.cluster}} by {host} < 0.15"
      threshold = 0.15
      no_data   = false
    }
    replicas = {
      name      = "API sem replicas disponiveis"
      query     = "max(last_5m):max:kubernetes_state.deployment.replicas_available{${local.cluster},kube_namespace:tech-challenge,kube_deployment:api} < 1"
      threshold = 1
      no_data   = true
    }
    os_errors = {
      name      = "Erro tecnico no processamento de OS"
      query     = "sum(last_5m):sum:techchallenge.os.failures{${local.scope},outcome:error}.as_count() > 0"
      threshold = 0
      no_data   = false
    }
  }
}

resource "datadog_monitor" "metrics" {
  for_each            = local.metric_monitors
  name                = "[TC3-10][${var.environment}] ${each.value.name}"
  type                = "metric alert"
  query               = each.value.query
  message             = "Investigar infraestrutura, APM e logs service:${local.service} env:${var.environment}. Usar correlation_id para localizar a requisicao. ${var.notification_recipients}"
  require_full_window = false
  notify_no_data      = each.value.no_data
  no_data_timeframe   = each.value.no_data ? 10 : null
  tags                = local.tags
  monitor_thresholds {
    critical = each.value.threshold
  }
}

resource "datadog_monitor" "health" {
  for_each          = toset(["live", "ready"])
  name              = "[TC3-10][${var.environment}] API health ${each.key}"
  type              = "service check"
  query             = "\"http.can_connect\".over(\"service:${local.service}\",\"env:${var.environment}\",\"check:${each.key}\").by(\"*\").last(3).count_by_status()"
  message           = "Healthcheck ${each.key} falhou. Verificar pods e, para readiness, conectividade PostgreSQL. ${var.notification_recipients}"
  notify_no_data    = true
  no_data_timeframe = 5
  tags              = local.tags
  monitor_thresholds {
    critical = 3
    ok       = 1
  }
}

resource "datadog_monitor" "api_errors" {
  name    = "[TC3-10][${var.environment}] Erros da API"
  type    = "log alert"
  query   = "logs(\"service:${local.service} env:${var.environment} status:error\").index(\"*\").rollup(\"count\").last(\"5m\") > 0"
  message = "Consultar exception, correlation_id e trace_id no log e abrir o trace relacionado. ${var.notification_recipients}"
  tags    = local.tags
  monitor_thresholds {
    critical = 0
  }
}

resource "datadog_service_level_objective" "availability" {
  name        = "[TC3-10][${var.environment}] Disponibilidade interna da API"
  type        = "monitor"
  description = "Meta academica de 99% em 7 dias com base nos checks de readiness e replicas. Mede disponibilidade interna; nao substitui um teste externo do ALB."
  monitor_ids = [datadog_monitor.health["ready"].id, datadog_monitor.metrics["replicas"].id]
  tags        = local.tags
  thresholds {
    timeframe = "7d"
    target    = 99
  }
}

output "monitor_ids" {
  value = merge({ for name, monitor in datadog_monitor.metrics : name => monitor.id }, { for name, monitor in datadog_monitor.health : name => monitor.id }, { api_errors = datadog_monitor.api_errors.id })
}

output "availability_slo_id" {
  value = datadog_service_level_objective.availability.id
}
