locals {
  apply_roles = { for name, role in local.managed_roles : name => role if role.mode == "apply" }
  application_roles = {
    for name, role in local.apply_roles : name => [
      for suffix in ["cluster", "nodes", "vpc-cni", "aws-load-balancer-controller"] :
      "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${role.suffix}-${suffix}"
    ]
  }
}

resource "aws_iam_role_policy" "apply" {
  for_each = local.apply_roles
  name     = "terraform-provisioning"
  role     = aws_iam_role.terraform[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ProvisionNetworkAndEKS"
        Effect   = "Allow"
        Action   = ["ec2:*", "eks:*"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource", "logs:TagLogGroup", "logs:UntagLogGroup"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/eks/${var.project_name}-${each.value.suffix}/cluster",
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/eks/${var.project_name}-${each.value.suffix}/cluster:*",
        ]
      },
      {
        Sid      = "ManageApplicationRoles"
        Effect   = "Allow"
        Action   = ["iam:CreateRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy", "iam:UpdateRole", "iam:UpdateRoleDescription", "iam:TagRole", "iam:UntagRole"]
        Resource = local.application_roles[each.key]
      },
      {
        Sid      = "ManageControllerPolicy"
        Effect   = "Allow"
        Action   = ["iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:TagPolicy", "iam:UntagPolicy"]
        Resource = "arn:aws:iam::${var.aws_account_id}:policy/${var.project_name}-${each.value.suffix}-load-balancer-controller"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
        Resource = local.application_roles[each.key]
        Condition = {
          ArnEquals = {
            "iam:PolicyARN" = concat(
              [for policy in ["AmazonEKSClusterPolicy", "AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryPullOnly", "AmazonEKS_CNI_Policy"] : "arn:aws:iam::aws:policy/${policy}"],
              ["arn:aws:iam::${var.aws_account_id}:policy/${var.project_name}-${each.value.suffix}-load-balancer-controller"],
            )
          }
        }
      },
      {
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = local.application_roles[each.key]
        Condition = { StringEquals = { "iam:PassedToService" = ["eks.amazonaws.com", "ec2.amazonaws.com"] } }
      },
      {
        Effect   = "Allow"
        Action   = ["iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider", "iam:UpdateOpenIDConnectProviderThumbprint", "iam:AddClientIDToOpenIDConnectProvider", "iam:RemoveClientIDFromOpenIDConnectProvider", "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider"]
        Resource = "arn:aws:iam::${var.aws_account_id}:oidc-provider/oidc.eks.${var.aws_region}.amazonaws.com/id/*"
      },
      {
        Effect    = "Allow"
        Action    = "iam:CreateServiceLinkedRole"
        Resource  = "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/*"
        Condition = { StringEquals = { "iam:AWSServiceName" = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "autoscaling.amazonaws.com", "elasticloadbalancing.amazonaws.com", "spot.amazonaws.com"] } }
      },
    ]
  })
}
