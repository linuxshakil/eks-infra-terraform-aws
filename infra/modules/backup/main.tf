############################################################
# Backup Bucket
#
# A private, versioned S3 bucket for RDS database dumps. Public
# access is fully blocked, and a 30-day lifecycle rule expires
# old backups automatically.
############################################################

resource "aws_s3_bucket" "backup" {
  bucket = var.bucket_name

  tags = {
    purpose    = "rds-backup"
    managed-by = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}
