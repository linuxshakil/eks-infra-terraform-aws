terraform {
  # This bucket belongs to the PROD AWS account, created by
  # bootstrap/envs/prod. It is a physically different bucket in a
  # physically different AWS account from the dev backend in
  # infra/envs/dev/backend.tf — there is no way for a mistaken
  # command in this folder to ever touch dev state.
  backend "s3" {
    bucket       = "eks-prod-001-tf-state"
    key          = "eks/prod/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
