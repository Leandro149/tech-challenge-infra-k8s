variable "aws_region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo dos recursos AWS."
  type        = string
  default     = "tech-challenge"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}$", var.project_name))
    error_message = "Use até 23 caracteres minúsculos, números e hífens, começando com letra, para respeitar o limite dos nomes IAM."
  }
}

variable "environment" {
  description = "Identificador do ambiente."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", var.environment))
    error_message = "Use até 10 caracteres minúsculos, números e hífens, começando com letra."
  }
}

variable "kubernetes_version" {
  description = "Versão Kubernetes oferecida pelo EKS na região escolhida."
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR IPv4 da VPC; reservar espaço para quatro subnets."
  type        = string
  default     = "10.30.0.0/16"

  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 4, 3)) && can(regex("^[0-9.]+/", var.vpc_cidr))
    error_message = "Informe um CIDR IPv4 válido que permita quatro subnets com quatro bits adicionais."
  }
}

variable "availability_zones" {
  description = "Duas AZs da região para subnets públicas e privadas."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Informe exatamente duas AZs distintas da região escolhida."
  }
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs autorizados no endpoint público do EKS (IP de saída do operador/CI)."
  type        = list(string)

  validation {
    condition = length(var.cluster_endpoint_public_access_cidrs) > 0 && alltrue([
      for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0"
    ])
    error_message = "Informe CIDRs IPv4 válidos e restritos; 0.0.0.0/0 não é permitido."
  }
}

variable "cluster_admin_principal_arns" {
  description = "ARNs IAM de roles/users administradores. Não use ARN STS de sessão assumida."
  type        = set(string)

  validation {
    condition = length(var.cluster_admin_principal_arns) > 0 && alltrue([
      for arn in var.cluster_admin_principal_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", arn))
    ])
    error_message = "Informe ao menos um ARN IAM válido de role ou user."
  }
}

variable "node_groups" {
  description = "Managed Node Groups. HPA escala pods; capacidade dos nodes é configurada aqui."
  type = map(object({
    instance_types = optional(list(string), ["t3.medium"])
    capacity_type  = optional(string, "ON_DEMAND")
    min_size       = optional(number, 2)
    desired_size   = optional(number, 2)
    max_size       = optional(number, 4)
    disk_size      = optional(number, 20)
  }))
  default = { general = {} }

  validation {
    condition = length(var.node_groups) > 0 && alltrue([
      for name, group in var.node_groups :
      can(regex("^[a-z][a-z0-9-]{0,19}$", name)) &&
      contains(["ON_DEMAND", "SPOT"], group.capacity_type) &&
      length(group.instance_types) > 0 && group.disk_size >= 20 &&
      group.min_size >= 1 && group.min_size <= group.desired_size && group.desired_size <= group.max_size &&
      floor(group.min_size) == group.min_size && floor(group.desired_size) == group.desired_size && floor(group.max_size) == group.max_size
    ])
    error_message = "Defina grupos com nomes válidos (até 20 caracteres), tipo ON_DEMAND/SPOT, instâncias, disco >= 20 e inteiros 1 <= min <= desired <= max."
  }
}

variable "tags" {
  description = "Tags adicionais dos recursos AWS."
  type        = map(string)
  default     = {}
}
