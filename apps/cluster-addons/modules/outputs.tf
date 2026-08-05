output "alb_controller_release" {
  value = helm_release.alb_controller.name
}

output "external_secrets_release" {
  value = helm_release.external_secrets.name
}

output "argocd_release" {
  value = helm_release.argocd.name
}

output "argocd_namespace" {
  value = kubernetes_namespace.argocd.metadata[0].name
}
