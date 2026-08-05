############################################################
# AWS Secrets Manager
#
# GCP: google_secret_manager_secret + secret_version, "auto"
# replication.
# AWS: aws_secretsmanager_secret + secret_version — the concept
# and API shape are almost identical.
############################################################

resource "aws_secretsmanager_secret" "app_db_password" {
  name                    = "app-db-password"
  recovery_window_in_days = 0 # deletes immediately, convenient for learning; use 7-30 for production
}

resource "aws_secretsmanager_secret_version" "app_db_password" {
  secret_id     = aws_secretsmanager_secret.app_db_password.id
  secret_string = var.db_password
}
