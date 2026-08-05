#!/bin/bash
set -euo pipefail

DATE=${1:-$(date +%F)}
BUCKET="s3://${BACKUP_BUCKET}"

echo "======================================="
echo "Starting Restore"
echo "======================================="

echo "Reading DB password from AWS Secrets Manager..."

DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id app-db-password \
  --query SecretString \
  --output text)

echo "Downloading SQL Backup..."

aws s3 cp \
  "${BUCKET}/pollapp-${DATE}.sql" .

echo "Restoring into RDS MySQL..."

mysql \
  --host="${DB_HOST}" \
  --user="${DB_USER}" \
  --password="${DB_PASSWORD}" \
  "${DB_NAME}" \
  < "pollapp-${DATE}.sql"

echo "Cleanup..."

rm -f "pollapp-${DATE}.sql"

echo "======================================="
echo "Restore Completed Successfully"
echo "======================================="
