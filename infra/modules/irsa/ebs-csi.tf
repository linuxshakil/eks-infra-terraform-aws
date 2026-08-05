############################################################
# IRSA — EBS CSI Driver
#
# Permission to actually create/attach/delete an EBS volume for
# a PVC (PersistentVolumeClaim). On GKE, the Persistent Disk CSI
# driver was built in and worked using node_sa's permissions;
# on EKS it needs its own dedicated IRSA role.
#
# NOTE: live-poll-app itself doesn't need a PVC — its only
# storage is RDS, outside the cluster. This addon is kept
# enabled anyway because it's a standard baseline capability for
# any EKS cluster (any future workload that does need a PVC can
# use it immediately, with no extra Terraform change).
############################################################

data "aws_iam_policy_document" "ebs_csi_trust" {
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
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

############################################################
# EBS CSI EKS Addon — attached here because it needs the IRSA
# role above (this role couldn't exist before the cluster module
# ran — see the note in the eks module).
############################################################

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn
}
