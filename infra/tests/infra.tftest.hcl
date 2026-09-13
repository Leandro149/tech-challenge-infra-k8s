# Plans com providers simulados: não acessam a conta AWS nem criam recursos.
mock_provider "aws" {
  override_during = plan
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/TEST" }] }]
      certificate_authority = [{ data = "dGVzdC1jYQ==" }]
      endpoint              = "https://test.eks.amazonaws.com"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/TEST"
    }
  }
}

mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [{ sha1_fingerprint = "0123456789012345678901234567890123456789" }]
    }
  }
}

variables {
  cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
  cluster_admin_principal_arns         = ["arn:aws:iam::123456789012:role/TechChallengeAdmin"]
}

run "network_and_cluster" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "A VPC deve ter duas subnets públicas e duas privadas."
  }

  assert {
    condition     = !aws_subnet.private["us-east-1a"].map_public_ip_on_launch && !aws_subnet.private["us-east-1b"].map_public_ip_on_launch
    error_message = "As subnets dos nodes não devem atribuir IP público."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access && aws_eks_cluster.this.vpc_config[0].public_access_cidrs == toset(["203.0.113.10/32"])
    error_message = "Endpoint privado deve estar ativo e o público restrito ao CIDR informado."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API" && !aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions
    error_message = "A administração deve ocorrer por Access Entries explícitas."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].scaling_config[0].desired_size == 2 && aws_eks_node_group.this["general"].ami_type == "AL2023_x86_64_STANDARD"
    error_message = "O grupo padrão deve usar dois nodes AL2023."
  }

  assert {
    condition     = jsondecode(aws_iam_role.irsa["aws-load-balancer-controller"].assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/TEST:sub"] == "system:serviceaccount:kube-system:aws-load-balancer-controller"
    error_message = "IRSA deve limitar a role ao service account do controller."
  }
}

run "reject_open_cluster_endpoint" {
  command = plan

  variables {
    cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "reject_sts_session_as_admin" {
  command = plan

  variables {
    cluster_admin_principal_arns = ["arn:aws:sts::123456789012:assumed-role/Admin/session"]
  }

  expect_failures = [var.cluster_admin_principal_arns]
}

run "reject_invalid_node_capacity" {
  command = plan

  variables {
    node_groups = { general = { min_size = 3, desired_size = 2, max_size = 4 } }
  }

  expect_failures = [var.node_groups]
}
