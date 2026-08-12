variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile name for the dev/test account. Leave null in CI."
  type        = string
  default     = null
}

variable "state_bucket_name" {
  type = string
}

variable "github_repository" {
  type = string
}
