variable "aws_account_id" {
  type        = string
  description = "Conta AWS do bootstrap e dos ambientes."
  default     = "213284176265"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Informe um ID AWS de 12 dígitos."
  }
}

variable "aws_region" {
  type        = string
  description = "Região dos buckets e clusters."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Prefixo dos recursos, igual ao project_name de infra/."
  default     = "tech-challenge"
}

variable "github_repository" {
  type        = string
  description = "Repositório autorizado no OIDC (owner/repo)."
  default     = "Leandro149/tech-challenge-infra-k8s"
}

variable "existing_github_oidc_provider_arn" {
  type        = string
  description = "ARN do provider GitHub existente na conta; null cria um provider."
  default     = null
}
