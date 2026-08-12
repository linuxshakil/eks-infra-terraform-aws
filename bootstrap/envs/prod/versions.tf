terraform {
  required_version = ">= 1.10.0" # 1.10+ needed for S3 Native State Locking (use_lockfile), used by infra/apps envs

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
