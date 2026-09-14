locals {
  use_existing_iam_role = var.existing_iam_role_arn != null
  enable_irsa           = !local.use_existing_iam_role
  cluster_role_arn      = local.use_existing_iam_role ? var.existing_iam_role_arn : aws_iam_role.cluster[0].arn
  node_role_arn         = local.use_existing_iam_role ? var.existing_iam_role_arn : aws_iam_role.nodes[0].arn

  irsa_accounts = {
    vpc-cni                      = "system:serviceaccount:kube-system:aws-node"
    aws-load-balancer-controller = "system:serviceaccount:kube-system:aws-load-balancer-controller"
  }
}

resource "aws_iam_role" "cluster" {
  count = local.use_existing_iam_role ? 0 : 1

  name = "${local.cluster_name}-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  count = local.use_existing_iam_role ? 0 : 1

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "nodes" {
  count = local.use_existing_iam_role ? 0 : 1

  name = "${local.cluster_name}-nodes"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = local.use_existing_iam_role ? toset([]) : toset(["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryPullOnly"])

  role       = aws_iam_role.nodes[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.key}"
}

data "tls_certificate" "oidc" {
  count = local.enable_irsa ? 1 : 0

  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  count = local.enable_irsa ? 1 : 0

  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "irsa" {
  for_each = local.enable_irsa ? local.irsa_accounts : {}

  name = "${local.cluster_name}-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.this[0].arn }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = each.value
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  count = local.enable_irsa ? 1 : 0

  role       = aws_iam_role.irsa["vpc-cni"].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Política oficial versionada junto do chart 3.5.0; consultar policies/README.md.
resource "aws_iam_policy" "load_balancer_controller" {
  count = local.enable_irsa ? 1 : 0

  name   = "${local.cluster_name}-load-balancer-controller"
  policy = file("${path.module}/policies/load-balancer-controller.json")
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  count = local.enable_irsa ? 1 : 0

  role       = aws_iam_role.irsa["aws-load-balancer-controller"].name
  policy_arn = aws_iam_policy.load_balancer_controller[0].arn
}
