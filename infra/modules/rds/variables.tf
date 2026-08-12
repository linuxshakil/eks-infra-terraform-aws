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
  description = "Security group of the EKS worker nodes — only this group is allowed to reach the DB on port 3306"
  type        = string
}

variable "instance_class" {
  description = "RDS instance size — smaller for dev/test, bigger for prod"
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "multi_az" {
  description = "Set true for prod; false is fine for dev/test"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  type    = number
  default = 7
}

variable "skip_final_snapshot" {
  description = "true is convenient for dev/test; set false for prod so a final snapshot is always taken on destroy"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "false for dev/test; true for prod so nobody can accidentally destroy the prod database"
  type        = bool
  default     = false
}
