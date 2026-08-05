variable "cluster_name" {
  description = "Name of the EKS cluster — subnet and VPC tags are derived from this"
  type        = string
}

variable "vpc_cidr" {
  description = "Overall CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to use (EKS requires a minimum of 2)"
  type        = number
  default     = 2
}
