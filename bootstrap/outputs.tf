output "terraform_state_bucket" {
  description = "S3 bucket where infra/ and apps/ Terraform state will be stored"
  value       = aws_s3_bucket.tf_state.bucket
}

output "github_actions_role_arn" {
  description = "Copy this value into GitHub Secret AWS_GITHUB_ACTIONS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
