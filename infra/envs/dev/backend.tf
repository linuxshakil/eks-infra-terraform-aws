terraform {
  # This bucket belongs to the DEV/TEST AWS account, created by
  # bootstrap/envs/dev. It is a physically different bucket in a
  # physically different AWS account from the prod backend in
  # infra/envs/prod/backend.tf — there is no way for a mistaken
  # command in this folder to ever touch prod state.
  backend "s3" {
    bucket       = "eks-dev-001-tf-state"
    key          = "eks/dev/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
