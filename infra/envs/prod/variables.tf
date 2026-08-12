variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile for the prod account. Leave null in CI."
  type        = string
  default     = null
}

variable "cluster_name" {
  type    = string
  default = "prod-eks-cluster"
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "db_instance_name" {
  type = string
}

variable "database_name" {
  type = string
}

variable "database_user" {
  type = string
}

variable "backup_bucket_name" {
  type = string
}
