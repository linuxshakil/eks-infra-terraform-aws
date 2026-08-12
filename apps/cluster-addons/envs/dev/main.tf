data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "eks-dev-001-tf-state"
    key    = "eks/dev/terraform.tfstate"
    region = "ap-south-1"
  }
}

module "cluster_addons" {
  source = "../../modules"

  cluster_name               = var.cluster_name
  vpc_id                     = var.vpc_id
  alb_controller_role_arn    = data.terraform_remote_state.infra.outputs.alb_controller_role_arn
  external_secrets_role_arn  = data.terraform_remote_state.infra.outputs.external_secrets_role_arn
  git_repo_url                = var.git_repo_url
  git_target_revision         = var.git_target_revision
  gitops_path                  = "gitops/overlays/dev"
}
