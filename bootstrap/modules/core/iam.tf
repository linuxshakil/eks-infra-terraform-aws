############################################################
# GitHub Actions OIDC Provider
#
# This registers GitHub's OIDC issuer as a trusted identity
# provider in IAM, so that a GitHub Actions workflow can prove
# its identity and receive temporary AWS credentials — without
# any long-lived access key ever being stored as a GitHub secret:
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
# The trust policy's condition restricts this role to only be
# assumable by tokens issued for our own repository — so no
# other GitHub repo, even one using the same OIDC provider,
# could assume this role.
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
