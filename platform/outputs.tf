output "namespaces" {
  description = "Namespaces gerenciados."
  value       = [for namespace in kubernetes_namespace_v1.this : namespace.metadata[0].name]
}

output "hpa_names" {
  description = "HPAs gerenciados."
  value       = [for hpa in kubernetes_horizontal_pod_autoscaler_v2.this : "${hpa.metadata[0].namespace}/${hpa.metadata[0].name}"]
}

output "demo_url" {
  description = "URL HTTP do ALB da demonstração, quando habilitada."
  value       = length(kubernetes_ingress_v1.demo) > 0 ? "http://${kubernetes_ingress_v1.demo[0].status[0].load_balancer[0].ingress[0].hostname}" : null
}
