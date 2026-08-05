variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "Without the https:// prefix, e.g. oidc.eks.ap-south-1.amazonaws.com/id/XXXX"
  type        = string
}

variable "backup_bucket_name" {
  description = "S3 bucket where DB dumps and uploads backups will be stored"
  type        = string
}
