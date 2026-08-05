terraform {
  # 1.10+ is required here because S3 Native State Locking
  # (the use_lockfile setting used in every backend.tf in this
  # repo) was introduced in Terraform 1.10.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
