terraform {
  # Dev account's own bucket — physically separate from prod's.
  backend "s3" {
    bucket       = "eks-dev-001-tf-state"
    key          = "apps/cluster-addons/dev/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
