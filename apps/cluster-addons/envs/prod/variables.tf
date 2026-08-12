variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "aws_profile" {
  type    = string
  default = null
}

variable "cluster_name" {
  type    = string
  default = "prod-eks-cluster"
}

variable "vpc_id" {
  type = string
}

variable "git_repo_url" {
  description = "The live-poll-app repo's git URL — a SEPARATE repo from this one. ArgoCD in the prod cluster watches gitops/overlays/prod in it."
  type        = string
}

variable "git_target_revision" {
  type    = string
  default = "main"
}
