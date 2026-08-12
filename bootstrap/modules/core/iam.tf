############################################################
# GitHub Actions OIDC Provider
#
# In GCP we built "Workload Identity Federation" (WIF) so
# GitHub Actions could access GCP resources without any
# long-lived JSON key. On AWS the same idea is called an
# "IAM OIDC Identity Provider" — the concept is exactly the
# same:
#
#   GitHub Actions -> OIDC token -> AWS STS AssumeRoleWithWebIdentity
#   -> temporary AWS credentials (no static key, ever)
############################################################

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.github.certificates[0].sha1_fingerprint
  ]
}

############################################################
# GitHub Actions IAM Role (assumed via OIDC)
#
# The trust policy only allows our own repo — similar to how
# GCP used "attribute_condition = assertion.repository == ..."
# to restrict which repo could use the identity.
############################################################

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only this specific GitHub repo (any branch) can assume this role
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                  = var.github_actions_role_name
  assume_role_policy    = data.aws_iam_policy_document.github_actions_trust.json
  max_session_duration = 3600
}

############################################################
# GitHub Actions Permissions
#
# For this learning project we attach AdministratorAccess so
# a beginner doesn't have to write 20 separate fine-grained
# policies just to get the pipeline running. This is called
# out again in the "Security Best Practices" section of the
# README — don't do this for a real production account.
############################################################

resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
