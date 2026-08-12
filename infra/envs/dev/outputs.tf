#############################################################
# RDS
#############################################################

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "rds_port" {
  value = module.rds.port
}

output "database_password" {
  value     = module.rds.database_password
  sensitive = true
}

#############################################################
# Secrets Manager
#############################################################

output "secret_manager_secret" {
  value = module.secrets_manager.secret_name
}

#############################################################
# Backup
#############################################################

output "backup_bucket_name" {
  value = module.backup.bucket_name
}

output "backup_role_arn" {
  value = module.irsa.backup_role_arn
}

#############################################################
# ECR
#############################################################

output "ecr_app_repository_url" {
  value = module.ecr_app.repository_url
}

output "ecr_backup_repository_url" {
  value = module.ecr_backup.repository_url
}

#############################################################
# Database
#############################################################

output "database_name" {
  value = var.database_name
}

output "database_user" {
  value = var.database_user
}

#############################################################
# IAM / IRSA
#############################################################

output "node_role_arn" {
  value = module.iam.node_role_arn
}

output "app_role_arn" {
  description = "IRSA role that the live-poll-app ServiceAccount will assume (bound to the Kubernetes SA via annotation in gitops/live-poll-app/serviceaccount.yaml)"
  value       = module.irsa.app_role_arn
}

output "external_secrets_role_arn" {
  value = module.irsa.external_secrets_role_arn
}

output "alb_controller_role_arn" {
  value = module.irsa.alb_controller_role_arn
}

output "ebs_csi_role_arn" {
  value = module.irsa.ebs_csi_role_arn
}

#############################################################
# EKS
#############################################################

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value     = module.eks.cluster_endpoint
  sensitive = true
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}
