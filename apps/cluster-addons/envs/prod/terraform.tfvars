region = "ap-south-1"

# aws_profile = "prod-account"   # uncomment for local runs

cluster_name = "prod-eks-cluster"

# Copy this from "terraform output vpc_id" after infra/envs/prod has been applied
vpc_id = "vpc-REPLACE_ME"

# The live-poll-app repo — a separate GitHub repo from this one
git_repo_url         = "https://github.com/yourusername/live-poll-app.git"
git_target_revision = "main"
