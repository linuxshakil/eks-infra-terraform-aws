provider "aws" {
  region = var.region
}

# The Kubernetes/Helm providers can only target this root module
# after the cluster is created — same pattern as the GKE root
# providers.tf (data.google_client_config there, an
# aws_eks_cluster_auth data source here).

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_cert)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_cert)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
