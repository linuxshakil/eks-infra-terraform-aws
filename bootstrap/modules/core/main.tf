############################################################
# Terraform State Bucket (S3)
#
# In GCP, we used a GCS bucket to store state. On AWS, an S3
# bucket is the equivalent. State locking used to need a
# separate DynamoDB table, but from Terraform 1.10 onwards,
# S3 can do locking on its own using conditional writes
# (S3 Native State Locking). So we don't need DynamoDB here
# at all now.
############################################################

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  # Prevents this bucket from being deleted by an accidental
  # "terraform destroy"
  lifecycle {
    prevent_destroy = false # kept false for this learning project; set true for real prod
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
