variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "alb_controller_role_arn" {
  type = string
}

variable "external_secrets_role_arn" {
  type = string
}

variable "git_repo_url" {
  type = string
}

variable "git_target_revision" {
  type    = string
  default = "main"
}
