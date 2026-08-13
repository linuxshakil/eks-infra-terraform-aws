############################################################
# IRSA — Application (live-poll-app)
#
# This role reads app-db-password from Secrets Manager, scoped
# to a specific ServiceAccount: namespace "app", ServiceAccount
# "app-sa". No other pod anywhere in the cluster can assume it.
#
# This role is created by Terraform, but nothing in
# live-poll-app-deploy ever needs to know its ARN value in
# order to *use* it — the ServiceAccount just needs to be
# annotated with it once. See the README section "Secret
# Management: Terraform vs GitHub Actions vs ArgoCD" for how
# this ARN moves from a Terraform output into a plain git file.
############################################################

data "aws_iam_policy_document" "app_trust" {
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
      values   = ["system:serviceaccount:app:app-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.cluster_name}-app-role"
  assume_role_policy = data.aws_iam_policy_document.app_trust.json
}

data "aws_iam_policy_document" "app_secrets_access" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = ["arn:aws:secretsmanager:*:*:secret:app-db-password*"]
  }
}

resource "aws_iam_role_policy" "app_secrets" {
  name   = "app-secrets-access"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_secrets_access.json
}
