############################################################
# ArgoCD
#
# This is the piece that changes how this repo deploys the
# application. Up to this point, every layer (network, EKS,
# RDS, IAM, even the ALB Controller and External Secrets
# Operator) is provisioned by Terraform because it is
# "platform" — it changes rarely and needs the safety of a
# reviewed plan/apply.
#
# The application itself (a separate git repo entirely — see
# var.git_repo_url — at some gitops/overlays/<env> path) is
# it changes on every code push, sometimes many times a day.
# ArgoCD is a GitOps controller that runs inside the cluster,
# continuously watches a path in a git repo, and makes the
# cluster's actual state match whatever is committed there —
# no `terraform apply` involved for app deploys at all.
#
# ArgoCD manages no cloud secrets of its own. It only applies
# Kubernetes manifests (Deployment, Service, Ingress,
# SecretStore, ExternalSecret) — none of which contain real
# secret material. The actual DB password still flows entirely
# through IRSA + External Secrets Operator, exactly as it does
# for every other IRSA-based workload in this repo. ArgoCD
# never sees, stores, or handles the password itself.
############################################################

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "7.7.11"

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      server = {
        # ClusterIP + "kubectl port-forward" for this learning
        # project, so we don't need a second ALB and a second
        # ACM certificate just to reach the ArgoCD UI. Point
        # this at an Ingress of its own if you want a permanent
        # URL for it.
        service = {
          type = "ClusterIP"
        }
      }

      configs = {
        params = {
          "server.insecure" = true
        }
      }
    })
  ]
}

############################################################
# ArgoCD Application — the "bootstrap" object
#
# This is the one and only piece of app-deployment configuration
# that Terraform touches. It doesn't deploy the app itself — it
# just tells ArgoCD "watch this repo, this path, this branch,
# and keep the cluster in sync with whatever you find there."
# Everything after this point (new image tags, replica counts,
# ingress changes) is a plain git commit to that other repo,
# not a Terraform change.
############################################################

resource "kubernetes_manifest" "live_poll_app" {
  # NOTE: kubernetes_manifest needs the "Application" CRD to
  # already exist in the cluster's API schema at plan time. Since
  # that CRD is installed by helm_release.argocd in this same
  # apply, the very first run needs two passes:
  #
  #   terraform apply -target=helm_release.argocd
  #   terraform apply
  #
  # After that first time, normal `terraform apply` works fine on
  # its own. This is a common, well-known Terraform + CRD
  # ordering quirk — not specific to ArgoCD.
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"

    metadata = {
      name      = "live-poll-app"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }

    spec = {
      project = "default"

      source = {
        repoURL        = var.git_repo_url
        targetRevision = var.git_target_revision
        path           = var.gitops_path
      }

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "app"
      }

      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }

        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  }

  depends_on = [
    helm_release.argocd
  ]
}
