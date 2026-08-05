output "repository_name" {
  value = aws_ecr_repository.backup.name
}

output "repository_url" {
  value = aws_ecr_repository.backup.repository_url
}
