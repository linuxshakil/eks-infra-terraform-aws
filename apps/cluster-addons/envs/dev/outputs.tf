output "alb_controller_release" {
  value = module.cluster_addons.alb_controller_release
}

output "external_secrets_release" {
  value = module.cluster_addons.external_secrets_release
}

output "argocd_release" {
  value = module.cluster_addons.argocd_release
}

output "argocd_namespace" {
  value = module.cluster_addons.argocd_namespace
}
