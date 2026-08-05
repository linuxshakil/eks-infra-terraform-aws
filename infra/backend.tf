terraform {
  # use_lockfile enables S3 Native State Locking (Terraform 1.10+),
  # so we don't need a separate DynamoDB table for locking anymore.
  backend "s3" {
    bucket       = "eks-prod-demo-001-tf-state"
    key          = "eks/prod/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
