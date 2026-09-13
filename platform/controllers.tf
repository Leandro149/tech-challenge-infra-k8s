resource "kubernetes_service_account_v1" "load_balancer_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = local.infra.load_balancer_controller_role_arn
    }
  }
}

resource "helm_release" "load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.5.0"
  namespace  = "kube-system"
  atomic     = true
  wait       = true
  timeout    = 600

  values = [yamlencode({
    clusterName  = local.infra.cluster_name
    region       = local.infra.aws_region
    vpcId        = local.infra.vpc_id
    replicaCount = 2
    serviceAccount = {
      create = false
      name   = kubernetes_service_account_v1.load_balancer_controller.metadata[0].name
    }
    # O TC3-06 usa Ingress; não depende de CRDs adicionais do Gateway API.
    controllerConfig = {
      featureGates = {
        ALBGatewayAPI      = false
        NLBGatewayAPI      = false
        GatewayListenerSet = false
      }
    }
  })]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"
  namespace  = "kube-system"
  atomic     = true
  wait       = true
  timeout    = 600

  values = [yamlencode({
    replicas = 2
  })]
}
