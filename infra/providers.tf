provider "aws" {
  region              = var.aws_region
  allowed_account_ids = var.aws_account_id == null ? null : [var.aws_account_id]

  default_tags {
    tags = merge(var.tags, {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    })
  }
}

data "aws_partition" "current" {}

locals {
  cluster_name = "${var.project_name}-${var.environment}"
  oidc_issuer  = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}
