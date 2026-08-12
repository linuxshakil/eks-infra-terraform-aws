module "bootstrap" {
  source = "../../modules/core"

  state_bucket_name = var.state_bucket_name
  github_repository = var.github_repository
}
