region = "ap-south-1"

cluster_name = "prod-eks-cluster"

# Copy this from "terraform output vpc_id" after infra/ has been applied
vpc_id = "vpc-REPLACE_ME"

# ArgoCD watches this repo/branch for gitops/live-poll-app changes
git_repo_url         = "https://github.com/yourusername/eks-infra-terraform.git"
git_target_revision = "main"
