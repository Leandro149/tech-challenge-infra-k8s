output "environment" {
  description = "Ambiente do cluster, usado para conferir a leitura do state."
  value       = var.environment
}

output "aws_region" {
  description = "Região do cluster."
  value       = var.aws_region
}

output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint da API Kubernetes."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "CA do cluster em base64."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "vpc_id" {
  description = "ID da VPC."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Subnets privadas dos nodes."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "public_subnet_ids" {
  description = "Subnets públicas para ALB."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "load_balancer_controller_role_arn" {
  description = "Role IRSA usada pelo Load Balancer Controller."
  value       = aws_iam_role.irsa["aws-load-balancer-controller"].arn
}

output "node_group_names" {
  description = "Managed Node Groups criados."
  value       = [for group in aws_eks_node_group.this : group.node_group_name]
}

output "configure_kubectl" {
  description = "Comando para configurar kubeconfig usando as credenciais AWS atuais."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}
