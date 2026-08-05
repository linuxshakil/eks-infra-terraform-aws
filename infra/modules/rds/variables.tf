variable "instance_identifier" {
  type = string
}

variable "database_name" {
  type = string
}

variable "database_user" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "eks_node_security_group_id" {
  description = "EKS worker nodes ka security group — sirf yahi se DB tak 3306 khulega"
  type        = string
}
