terraform {
  backend "s3" {
    bucket       = "eks-prod-demo-001-tf-state"
    key          = "apps/cluster-addons/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
