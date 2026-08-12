# This bootstrap has no remote backend of its own (it's the thing
# that CREATES the remote backend for infra/ and apps/cluster-addons/
# in this same account) — state stays local to this folder. Keep a
# backup of dev/terraform.tfstate somewhere safe; if you lose it,
# the fix is just re-running "terraform apply" here again (these
# resources are cheap and safe to recreate).
#
# "profile" lets you run this against the dev AWS account locally
# using a named AWS CLI profile (aws configure --profile dev-account).
# In CI, this is left unset and the role comes from OIDC instead
# (see .github/workflows/bootstrap-dev.yml).
provider "aws" {
  region  = var.region
  profile = var.aws_profile
}
