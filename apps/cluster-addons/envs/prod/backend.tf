terraform {
  # Prod account's own bucket — physically separate from dev's.
  backend "s3" {
    bucket       = "eks-prod-001-tf-state"
    key          = "apps/cluster-addons/prod/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
