output "cluster_name" {
  value = aws_eks_cluster.primary.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.primary.endpoint
}

output "cluster_ca_cert" {
  value = aws_eks_cluster.primary.certificate_authority[0].data
}

output "cluster_arn" {
  value = aws_eks_cluster.primary.arn
}

output "oidc_provider_arn" {
  description = "Needed for IRSA — used inside IAM trust policies"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  value = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

output "cluster_security_group_id" {
  description = "EKS's default cluster security group — nodes use this. The RDS security group allows port 3306 from this group."
  value       = aws_eks_cluster.primary.vpc_config[0].cluster_security_group_id
}
