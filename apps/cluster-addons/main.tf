############################################################
# Cluster Add-ons project
#
# This project explicitly installs on AWS what GKE gave you
# built in, plus the GitOps controller that replaces
# Terraform-driven app deployment:
#   1. AWS Load Balancer Controller — replaces the GCE Ingress
#      controller (which was free/built into GKE), provisions ALBs.
#   2. External Secrets Operator — same as the GCP version,
#      syncs Kubernetes Secrets from Secrets Manager.
#   3. ArgoCD — watches this git repo's gitops/live-poll-app
#      folder and keeps the cluster's actual state in sync with
#      whatever is committed there. From this point on, Terraform
#      never deploys the application itself — it only sets up
#      the platform that ArgoCD then uses.
#
# All the IAM roles (IRSA) these controllers need were already
# created in the "infra/" project (module.irsa) — here we just
# read their ARNs from remote_state and annotate each
# ServiceAccount with them.
############################################################

data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "eks-prod-demo-001-tf-state"
    key    = "eks/prod/terraform.tfstate"
    region = "ap-south-1"
  }
}

module "cluster_addons" {
  source = "./modules"

  cluster_name               = var.cluster_name
  vpc_id                     = var.vpc_id
  alb_controller_role_arn    = data.terraform_remote_state.infra.outputs.alb_controller_role_arn
  external_secrets_role_arn  = data.terraform_remote_state.infra.outputs.external_secrets_role_arn
  git_repo_url                = var.git_repo_url
  git_target_revision         = var.git_target_revision
}
