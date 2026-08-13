############################################################
# IRSA — Backup CronJob
#
# This role gives the backup job permission to create RDS
# snapshots, read/write the backup S3 bucket, and read the DB
# password from Secrets Manager (needed to run mysqldump).
############################################################

data "aws_iam_policy_document" "backup_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:app:rds-backup"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.cluster_name}-rds-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_trust.json
}

data "aws_iam_policy_document" "backup_access" {
  statement {
    effect = "Allow"

    actions = [
      "rds:DescribeDBInstances",
      "rds:CreateDBSnapshot",
      "rds:DescribeDBSnapshots"
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject"
    ]

    resources = [
      "arn:aws:s3:::${var.backup_bucket_name}",
      "arn:aws:s3:::${var.backup_bucket_name}/*"
    ]
  }

  statement {
    # The backup script needs the app's DB password (to run
    # mysqldump), so it can read this secret too
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = ["arn:aws:secretsmanager:*:*:secret:app-db-password*"]
  }
}

resource "aws_iam_role_policy" "backup" {
  name   = "rds-backup-access"
  role   = aws_iam_role.backup.id
  policy = data.aws_iam_policy_document.backup_access.json
}
