############################################################
# EKS Cluster
#
# GCP's "google_container_cluster" is "aws_eks_cluster" here.
# The difference: GKE offers a fully-managed control plane and
# a node pool together in one resource block. On EKS, the
# control plane (aws_eks_cluster) and worker nodes
# (aws_eks_node_group) are always two separate resources — a
# bit more explicit, but the concept is the same: "control
# plane is managed by the cloud, the data plane (nodes) runs
# inside your own account".
############################################################

resource "aws_eks_cluster" "primary" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = concat(var.private_subnet_ids, var.public_subnet_ids)

    # Similar to GCP's "private_cluster_config" — the control
    # plane endpoint is both public (so CI/CD and kubectl can
    # connect) and private (so nodes inside the VPC can talk to
    # it directly). For production, restrict public access to
    # specific CIDRs (this does the same job as GKE's
    # master_authorized_networks, via public_access_cidrs).
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # AWS equivalent of GKE's "logging_config" / "monitoring_config"
  # — all of this goes into CloudWatch Logs.
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
# This is the AWS equivalent of GCP's "Workload Identity".
# Every EKS cluster exposes its own OIDC issuer; we register
# that issuer as a "trusted identity provider" in IAM. After
# that, any Kubernetes ServiceAccount, with the right
# annotation, can "assume" an IAM Role — just like GCP
# Workload Identity's "serviceAccount:PROJECT.svc.id.goog[ns/sa]"
# pattern.
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

  # GKE had "management { auto_upgrade = true, auto_repair = true }"
  # — EKS managed node groups have this behaviour built in: AWS
  # replaces unhealthy nodes on its own, and "update_config"
  # controls rolling upgrades.

  depends_on = [
    aws_eks_cluster.primary
  ]
}

############################################################
# EKS Add-ons (equivalent of GKE's "addons_config" block)
#
# GKE had horizontal_pod_autoscaling and http_load_balancing as
# built-in addons. EKS also manages some things as "add-ons" —
# here we enable coredns, kube-proxy, vpc-cni, and
# aws-ebs-csi-driver (kept enabled as a baseline capability, even
# though live-poll-app itself has no PVC — see the note in
# modules/irsa/ebs-csi.tf).
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
# This avoids a dependency cycle. README Section 13 explains
# this sequencing in detail, since it's the biggest structural
# difference from GKE.
############################################################
