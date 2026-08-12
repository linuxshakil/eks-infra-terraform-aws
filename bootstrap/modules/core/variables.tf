variable "state_bucket_name" {
  description = "Globally unique S3 bucket name that will store the Terraform remote state for this one AWS account/environment"
  type        = string
}

variable "github_repository" {
  description = "owner/repo of the eks-infra-terraform repo, e.g. myuser/eks-infra-terraform"
  type        = string
}

variable "github_actions_role_name" {
  type    = string
  default = "github-actions-eks-role"
}
