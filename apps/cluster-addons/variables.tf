variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "git_repo_url" {
  description = "This repository's git URL, e.g. https://github.com/yourusername/eks-infra-terraform.git — ArgoCD watches this to find gitops/live-poll-app"
  type        = string
}

variable "git_target_revision" {
  description = "Branch or tag ArgoCD should track"
  type        = string
  default     = "main"
}
