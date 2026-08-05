variable "region" {
  description = "AWS region where bootstrap resources (state bucket, OIDC provider) will be created"
  type        = string
  default     = "ap-south-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name that will store the Terraform remote state"
  type        = string
}

variable "github_repository" {
  description = "owner/repo format, e.g. myuser/eks-infra-terraform"
  type        = string
}

variable "github_actions_role_name" {
  description = "Name of the IAM Role that GitHub Actions will assume through OIDC"
  type        = string
  default     = "github-actions-eks-role"
}
