region = "ap-south-1"

# aws_profile = "prod-account"   # uncomment for local runs

cluster_name = "prod-eks-cluster"

# Copy this from "terraform output vpc_id" after infra/envs/prod has been applied
vpc_id = "vpc-REPLACE_ME"

# The live-poll-app-deploy repo — GitOps manifests only, no app
# source code and no Terraform. A THIRD repo, separate from both
# this one and from live-poll-app (which holds only app source).
git_repo_url         = "https://github.com/linuxshakil/live-poll-app-deploy.git"
git_target_revision = "main"
