output "secret_name" {
  value = aws_secretsmanager_secret.app_db_password.name
}

output "secret_arn" {
  value = aws_secretsmanager_secret.app_db_password.arn
}
