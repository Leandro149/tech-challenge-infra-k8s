mock_provider "datadog" {}

variables {
  cluster_name = "tech-challenge-prod"
}

run "tc3_10_monitors" {
  command = plan
  assert {
    condition     = length(datadog_monitor.metrics) == 4 && length(datadog_monitor.health) == 2
    error_message = "Cobrir CPU, memoria, replicas, falhas de OS e ambos healthchecks."
  }
  assert {
    condition     = datadog_monitor.metrics["replicas"].notify_no_data && datadog_monitor.health["ready"].notify_no_data && !datadog_monitor.metrics["os_errors"].notify_no_data
    error_message = "Ausencia de telemetria de disponibilidade deve alertar; ausencia de erros de OS nao."
  }
  assert {
    condition     = strcontains(datadog_monitor.metrics["os_errors"].query, "outcome:error") && datadog_service_level_objective.availability.thresholds[0].target == 99
    error_message = "Distinguir erros tecnicos de rejeicoes e definir meta de disponibilidade."
  }
}
