############################################################
# EKS Node Role  (equivalent of GCP's "node_sa")
#
# On GKE, the node pool used a dedicated Google Service Account
# (node_sa) with roles/logging.logWriter, monitoring.metricWriter,
# artifactregistry.reader, and so on. On AWS, worker node EC2
# instances also use an IAM Role (attached via an Instance
# Profile) with equivalent managed policies.
############################################################

data "aws_iam_policy_document" "eks_node_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_trust.json
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  # Equivalent of roles/logging.logWriter + roles/monitoring —
  # lets the node join the cluster and report basic health
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  # Lets the VPC-CNI plugin manage network interfaces
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  # Equivalent of roles/artifactregistry.reader — lets the node
  # pull container images
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  # Optional but recommended: gives shell access to nodes via
  # SSM Session Manager for troubleshooting, without needing SSH keys
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
