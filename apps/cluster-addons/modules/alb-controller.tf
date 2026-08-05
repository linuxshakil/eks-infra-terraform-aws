############################################################
# AWS Load Balancer Controller
#
# This Helm chart watches the Kubernetes "Ingress" objects used
# used in gitops/live-poll-app and automatically provisions an Application
# Load Balancer (ALB) — it does the same job as GKE's built-in
# GCE Ingress controller, except on EKS you have to install it
# yourself.
############################################################

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = var.alb_controller_role_arn
    }

    labels = {
      "app.kubernetes.io/name" = "aws-load-balancer-controller"
    }
  }
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.9.2"

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      clusterName = var.cluster_name

      serviceAccount = {
        create = false
        name   = kubernetes_service_account.alb_controller.metadata[0].name
      }

      vpcId = var.vpc_id
    })
  ]

  depends_on = [
    kubernetes_service_account.alb_controller
  ]
}
