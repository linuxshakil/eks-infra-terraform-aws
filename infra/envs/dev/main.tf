#############################################################
# Network
#############################################################

module "network" {
  source = "../../modules/network"

  cluster_name = var.cluster_name
}

#############################################################
# IAM — core cluster + node roles (no OIDC dependency yet)
#############################################################

module "iam" {
  source = "../../modules/iam"

  cluster_name = var.cluster_name
}

#############################################################
# EKS Cluster + Node Group + OIDC provider
#############################################################

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  node_instance_type = var.node_instance_type
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  public_subnet_ids  = module.network.public_subnet_ids
  cluster_role_arn   = module.iam.cluster_role_arn
  node_role_arn      = module.iam.node_role_arn

  # Dev only needs one worker node most of the time — override the
  # module's default sizing here to keep this environment cheap.
  node_desired_size = 1
  node_min_size     = 1
  node_max_size     = 3

  depends_on = [
    module.network,
    module.iam
  ]
}

#############################################################
# IRSA — workload-level IAM roles (needs EKS OIDC provider)
#############################################################

module "irsa" {
  source = "../../modules/irsa"

  cluster_name       = var.cluster_name
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  backup_bucket_name = var.backup_bucket_name

  depends_on = [
    module.eks
  ]
}

#############################################################
# RDS (MySQL)
#############################################################

module "rds" {
  source = "../../modules/rds"

  instance_identifier = var.db_instance_name
  database_name       = var.database_name
  database_user       = var.database_user

  vpc_id                      = module.network.vpc_id
  private_subnet_ids          = module.network.private_subnet_ids
  eks_node_security_group_id = module.eks.cluster_security_group_id

  # Dev/test sizing — small, single-AZ, safe to tear down without a
  # final snapshot. Compare against infra/envs/prod/main.tf.
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  multi_az                = false
  backup_retention_period = 3
  skip_final_snapshot     = true
  deletion_protection     = false

  depends_on = [
    module.network,
    module.eks
  ]
}

#############################################################
# Secrets Manager
#############################################################

module "secrets_manager" {
  source = "../../modules/secrets-manager"

  db_password = module.rds.database_password

  depends_on = [
    module.rds
  ]
}

#############################################################
# ECR
#############################################################

module "ecr_app" {
  source = "../../modules/ecr"

  repository_name = "live-poll-app"
}

module "ecr_backup" {
  source = "../../modules/ecr"

  repository_name = "backup-images"
}

#############################################################
# Backup (S3 bucket)
#############################################################

module "backup" {
  source = "../../modules/backup"

  bucket_name = var.backup_bucket_name
}
