############################################################
# IRSA — AWS Load Balancer Controller
#
# On GKE, the "gce" Ingress class was built in — no extra
# controller had to be installed. On EKS, creating an ALB
# Ingress needs a Helm-installed controller called "AWS Load
# Balancer Controller" (installed in apps/cluster-addons). Its
# ServiceAccount assumes this role via IRSA so it can
# create/manage ALBs, Target Groups, and Security Groups.
############################################################

data "aws_iam_policy_document" "alb_controller_trust" {
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
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.cluster_name}-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_trust.json
}

# Official AWS Load Balancer Controller IAM policy (published by
# AWS). For production it's better to load this from a file;
# for readability we keep that same official policy JSON right
# next to this module (iam-policy-alb-controller.json).
resource "aws_iam_role_policy" "alb_controller" {
  name   = "alb-controller-access"
  role   = aws_iam_role.alb_controller.id
  policy = file("${path.module}/iam-policy-alb-controller.json")
}
