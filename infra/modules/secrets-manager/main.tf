############################################################
# AWS Secrets Manager
#
# Stores the RDS password securely. Applications never read this
# value directly from Terraform — they read it at runtime via
# IRSA + the External Secrets Operator (see infra/modules/irsa
# and the live-poll-app-deploy repo's secretstore.yaml).
############################################################

resource "aws_secretsmanager_secret" "app_db_password" {
  name                    = "app-db-password"
  recovery_window_in_days = 0 # deletes immediately, convenient for learning; use 7-30 for production
}

resource "aws_secretsmanager_secret_version" "app_db_password" {
  secret_id     = aws_secretsmanager_secret.app_db_password.id
  secret_string = var.db_password
}
