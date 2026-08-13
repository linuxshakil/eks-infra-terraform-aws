############################################################
# EKS Cluster
#
# The control plane (aws_eks_cluster) and the worker nodes
# (aws_eks_node_group, below) are always two separate resources
# on EKS: AWS manages and runs the control plane for you; the
# worker nodes are ordinary EC2 instances that run inside your
# own account and register themselves with that control plane.
############################################################

resource "aws_eks_cluster" "primary" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = concat(var.private_subnet_ids, var.public_subnet_ids)

    # The control plane endpoint is both public (so CI/CD and
    # kubectl can connect from outside the VPC) and private (so
    # nodes inside the VPC can talk to it directly, without
    # routing out to the internet and back). For production,
    # restrict public access to specific CIDRs via
    # public_access_cidrs instead of leaving it fully open.
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Cluster control-plane logs — sent to CloudWatch Logs.
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }
}

############################################################
# OIDC Provider for IRSA (IAM Roles for Service Accounts)
#
# Every EKS cluster exposes its own OIDC issuer URL, generated
# the moment the cluster is created. Registering that issuer as
# a trusted identity provider in IAM is what makes IRSA possible:
# any Kubernetes ServiceAccount, annotated with an IAM role ARN,
# can then "assume" that role and receive temporary AWS
# credentials — no password or access key involved anywhere.
############################################################

data "tls_certificate" "eks" {
  url = aws_eks_cluster.primary.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.primary.identity[0].oidc[0].issuer

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.eks.certificates[0].sha1_fingerprint
  ]
}

############################################################
# Managed Node Group
############################################################

resource "aws_eks_node_group" "primary" {
  cluster_name    = aws_eks_cluster.primary.name
  node_group_name = "${var.cluster_name}-pool"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  instance_types = [var.node_instance_type]
  disk_size      = 20

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    env = "production"
  }

  tags = {
    Name = "${var.cluster_name}-node"
  }

  # Managed node groups handle unhealthy-node replacement and
  # rolling upgrades automatically (governed by update_config
  # above) — no separate auto-repair/auto-upgrade configuration
  # is needed.

  depends_on = [
    aws_eks_cluster.primary
  ]
}

############################################################
# EKS Add-ons
#
# coredns, kube-proxy, and vpc-cni are the baseline add-ons
# every cluster needs. aws-ebs-csi-driver is kept enabled too,
# as a general-purpose capability, even though live-poll-app
# itself has no PVC — see the note in modules/irsa/ebs-csi.tf.
############################################################

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.primary.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.primary.name
  addon_name   = "coredns"

  depends_on = [aws_eks_node_group.primary]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.primary.name
  addon_name   = "kube-proxy"
}

############################################################
# NOTE — the aws-ebs-csi-driver addon needs IRSA (IAM Roles
# for Service Accounts), and IRSA depends on this cluster's
# OIDC provider, which has only just been created above. So
# that addon is not defined in this module — it lives in
# "modules/irsa" instead (which runs right after this module).
# This avoids a dependency cycle: the IRSA role needs the OIDC
# provider to exist first, and the addon needs the IRSA role to
# exist first, so they can't both be created in this same module.
############################################################
