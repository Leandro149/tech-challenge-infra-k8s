variable "infra_state_backend" {
  description = "Backend do state de infra/: local ou s3."
  type        = string
  default     = "local"

  validation {
    condition     = contains(["local", "s3"], var.infra_state_backend)
    error_message = "Use local ou s3."
  }
}

variable "infra_state_config" {
  description = "Configuração para ler o state de infra/. O caminho local é relativo a platform/."
  type        = map(string)
  default     = { path = "../infra/terraform.tfstate" }
}

variable "namespaces" {
  description = "Namespaces gerenciados por este repositório."
  type        = set(string)
  default     = ["tech-challenge", "observability"]

  validation {
    condition = length(var.namespaces) > 0 && alltrue([
      for name in var.namespaces :
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", name)) &&
      !contains(["default", "kube-system", "kube-public", "kube-node-lease"], name)
    ])
    error_message = "Informe namespaces DNS válidos de até 63 caracteres, sem os namespaces nativos do cluster."
  }
}

variable "enable_demo" {
  description = "Cria aplicação de exemplo, Service, Ingress ALB e HPA."
  type        = bool
  default     = true
}

variable "demo_namespace" {
  description = "Namespace do exemplo; deve pertencer à lista namespaces."
  type        = string
  default     = "tech-challenge"

  validation {
    condition     = !var.enable_demo || contains(var.namespaces, var.demo_namespace)
    error_message = "Inclua demo_namespace em namespaces quando enable_demo=true."
  }
}

variable "demo_image" {
  description = "Imagem do exemplo oficial Kubernetes para demonstrar HPA por CPU."
  type        = string
  default     = "registry.k8s.io/hpa-example:latest"
}

variable "demo_ingress_cidrs" {
  description = "CIDRs que podem acessar o ALB da demonstração por HTTP."
  type        = list(string)

  validation {
    condition = length(var.demo_ingress_cidrs) > 0 && alltrue([
      for cidr in var.demo_ingress_cidrs : can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0"
    ])
    error_message = "Informe CIDRs IPv4 restritos e válidos; 0.0.0.0/0 não é permitido."
  }
}

variable "hpa_workloads" {
  description = "HPAs para Deployments existentes, publicados pelos repositórios das aplicações."
  type = map(object({
    namespace       = string
    deployment_name = string
    min_replicas    = optional(number, 2)
    max_replicas    = optional(number, 5)
    cpu_utilization = optional(number, 70)
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, hpa in var.hpa_workloads :
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", name)) && name != "tc3-demo" &&
      contains(var.namespaces, hpa.namespace) &&
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", hpa.deployment_name)) &&
      hpa.min_replicas >= 1 && hpa.min_replicas <= hpa.max_replicas &&
      floor(hpa.min_replicas) == hpa.min_replicas && floor(hpa.max_replicas) == hpa.max_replicas &&
      hpa.cpu_utilization >= 1 && hpa.cpu_utilization <= 100 && floor(hpa.cpu_utilization) == hpa.cpu_utilization
    ])
    error_message = "Use nomes DNS válidos de até 63 caracteres (tc3-demo é reservado), namespace gerenciado, inteiros 1 <= min <= max e CPU entre 1 e 100."
  }
}
