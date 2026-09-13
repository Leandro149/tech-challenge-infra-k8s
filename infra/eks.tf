resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 7
}

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  vpc_config {
    subnet_ids              = [for subnet in aws_subnet.private : subnet.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  depends_on = [aws_iam_role_policy_attachment.cluster, aws_cloudwatch_log_group.cluster]
}

resource "aws_eks_access_entry" "admin" {
  for_each = var.cluster_admin_principal_arns

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.key
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = var.cluster_admin_principal_arns

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin[each.key].principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

data "aws_eks_addon_version" "this" {
  for_each = toset(["vpc-cni", "kube-proxy", "coredns"])

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

# O CNI precisa da role anotada antes que os nodes inicializem a rede dos pods.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.this["vpc-cni"].version
  service_account_role_arn    = aws_iam_role.irsa["vpc-cni"].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_iam_role_policy_attachment.vpc_cni]
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = [for subnet in aws_subnet.private : subnet.id]
  instance_types  = each.value.instance_types
  capacity_type   = each.value.capacity_type
  ami_type        = "AL2023_x86_64_STANDARD"
  disk_size       = each.value.disk_size
  version         = var.kubernetes_version
  labels          = { "workload-group" = each.key }

  scaling_config {
    min_size     = each.value.min_size
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes,
    aws_eks_addon.vpc_cni,
    aws_route.private_internet,
    aws_route_table_association.private,
  ]
}

resource "aws_eks_addon" "this" {
  for_each = toset(["kube-proxy", "coredns"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_node_group.this]
}
