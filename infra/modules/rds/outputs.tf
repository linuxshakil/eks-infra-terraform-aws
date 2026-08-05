output "instance_identifier" {
  value = aws_db_instance.app.identifier
}

output "endpoint" {
  description = "Equivalent of GCP's 'private_ip' — the app connects using this host"
  value       = aws_db_instance.app.address
}

output "port" {
  value = aws_db_instance.app.port
}

output "database_name" {
  value = aws_db_instance.app.db_name
}

output "database_user" {
  value = aws_db_instance.app.username
}

output "database_password" {
  value     = random_password.db_password.result
  sensitive = true
}

output "security_group_id" {
  value = aws_security_group.rds.id
}
