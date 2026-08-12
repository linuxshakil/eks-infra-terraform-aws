############################################################
# External Secrets Operator
#
# Same chart and pattern as the GCP version — only the
# provider name changes: instead of the GCP Secret Manager
# provider, this Operator's "aws" (Secrets Manager) provider
# will be used by the SecretStore manifests in the live-poll-app-deploy repo.
############################################################

resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

resource "kubernetes_service_account" "external_secrets" {
  metadata {
    name      = "external-secrets"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = var.external_secrets_role_arn
    }
  }
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = kubernetes_namespace.external_secrets.metadata[0].name
  create_namespace = false
  version          = "0.19.2"

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      serviceAccount = {
        create = false
        name   = kubernetes_service_account.external_secrets.metadata[0].name
      }
    })
  ]

  depends_on = [
    kubernetes_service_account.external_secrets
  ]
}
