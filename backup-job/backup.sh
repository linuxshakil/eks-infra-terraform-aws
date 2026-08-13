#!/bin/bash
set -euo pipefail

# Plain RDS MySQL has no built-in "export straight to S3" feature
# (Aurora MySQL does, but plain RDS MySQL doesn't) — so this uses
# the classic, most portable approach instead: dump the database
# with mysqldump, then upload the dump file with "aws s3 cp".
#
# Note: live-poll-app has no PVC/uploads folder — all of its state
# lives in RDS, so this script only needs to back up the database,
# nothing else.

DATE=$(date +%F)
BUCKET="s3://${BACKUP_BUCKET}"

echo "======================================="
echo "Starting Backup : ${DATE}"
echo "======================================="

echo "Reading DB password from AWS Secrets Manager..."

DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id app-db-password \
  --query SecretString \
  --output text)

echo "Dumping RDS MySQL database..."

mysqldump \
  --host="${DB_HOST}" \
  --user="${DB_USER}" \
  --password="${DB_PASSWORD}" \
  --single-transaction \
  --quick \
  --databases "${DB_NAME}" \
  > "pollapp-${DATE}.sql"

echo "Uploading SQL dump to S3..."

aws s3 cp \
  "pollapp-${DATE}.sql" \
  "${BUCKET}/pollapp-${DATE}.sql"

rm -f "pollapp-${DATE}.sql"

echo "======================================="
echo "Backup completed successfully"
echo "======================================="
