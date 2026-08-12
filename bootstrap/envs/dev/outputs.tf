output "terraform_state_bucket" {
  value = module.bootstrap.terraform_state_bucket
}

output "github_actions_role_arn" {
  description = "Copy into the DEV GitHub Environment's AWS_ROLE_ARN secret"
  value       = module.bootstrap.github_actions_role_arn
}
