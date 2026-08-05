# EKS Production Infrastructure on AWS — Terraform + GitOps (ArgoCD)

A production-style, end-to-end **Infrastructure as Code** project that provisions a private EKS cluster on AWS and runs a small real-time application on top of it — split cleanly between **Terraform** (which owns the platform: network, cluster, database, secrets, IAM) and **ArgoCD** (which owns the application: what's running, which image tag, how many replicas).

This is a **1:1 AWS port** of an existing GCP/GKE project, with one deliberate architectural upgrade over the original: instead of Terraform deploying the application directly, this version uses **GitOps** — Terraform provisions the platform and installs ArgoCD, and from that point on, the application is deployed purely by committing to a git folder. This README exists to make three things clear, with worked examples from this exact codebase:

1. How to actually run this end to end, even coming from zero AWS experience.
2. How Terraform, GitHub Actions, and ArgoCD each touch **secrets** differently — and why only one of the three ever sees a real password.
3. Every GCP concept mapped to its AWS equivalent, since that's usually the hardest part of moving a project between clouds.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [GCP → AWS Concept Map](#2-gcp--aws-concept-map)
3. [Architecture](#3-architecture)
4. [Repository Structure](#4-repository-structure)
5. [Technologies Used](#5-technologies-used)
6. [Prerequisites](#6-prerequisites)
7. [Install Everything](#7-install-everything)
8. [Terraform Core Concepts](#8-terraform-core-concepts)
9. [Why Split Platform, Add-ons, and App Like This?](#9-why-split-platform-add-ons-and-app-like-this)
10. [Bootstrap](#10-bootstrap)
11. [Infrastructure (`infra/`)](#11-infrastructure-infra)
12. [Module by Module Explanation](#12-module-by-module-explanation)
13. [IRSA — The AWS Equivalent of Workload Identity](#13-irsa--the-aws-equivalent-of-workload-identity)
14. [Apps Layer — Cluster Add-ons (incl. ArgoCD)](#14-apps-layer--cluster-add-ons-incl-argocd)
15. [The Application — `live-poll-app`](#15-the-application--live-poll-app)
16. [GitOps — `gitops/live-poll-app`](#16-gitops--gitopslive-poll-app)
17. [ACM Certificate & Domain Setup](#17-acm-certificate--domain-setup)
18. [Reading Data Across Projects — `terraform_remote_state`](#18-reading-data-across-projects--terraform_remote_state)
19. [GitHub Actions + OIDC](#19-github-actions--oidc)
20. [**Secret Management: Terraform vs GitHub Actions vs ArgoCD**](#20-secret-management-terraform-vs-github-actions-vs-argocd)
21. [Terraform Backend](#21-terraform-backend)
22. [State File](#22-state-file)
23. [Deployment Walkthrough](#23-deployment-walkthrough)
24. [Verification Commands](#24-verification-commands)
25. [Backup & Restore](#25-backup--restore)
26. [Destroy Walkthrough](#26-destroy-walkthrough)
27. [Cost Estimation](#27-cost-estimation)
28. [Security Best Practices](#28-security-best-practices)
29. [Troubleshooting](#29-troubleshooting)
30. [FAQ](#30-faq)
31. [Interview Questions](#31-interview-questions)
32. [Future Improvements](#32-future-improvements)

---

## 1. Introduction

This repository builds a real Kubernetes platform on AWS, split into **three independently-deployable Terraform projects** and **one GitOps-deployed application**:

| # | Project | Tool | What it owns | Changes how often? |
|---|---|---|---|---|
| 1 | `bootstrap/` | Terraform | State bucket + GitHub OIDC identity | Once, ever |
| 2 | `infra/` | Terraform | VPC, EKS, RDS, IAM/IRSA, Secrets Manager, ECR, Backup bucket | Rarely |
| 3 | `apps/cluster-addons/` | Terraform | AWS Load Balancer Controller, External Secrets Operator, **ArgoCD** (Helm) | Rarely |
| 4 | `gitops/live-poll-app/` | **ArgoCD (no Terraform)** | Namespace, Deployment, Service, Ingress, SecretStore, ExternalSecret | Often — every code push |

The first three are exactly the same "layered Terraform" pattern the GCP original used: infrastructure that changes rarely is isolated from things that change often. The fourth is new: **the application itself is no longer a Terraform project at all.** It's a folder of plain Kubernetes YAML that ArgoCD continuously applies. A `git push` to `app/**` triggers a GitHub Actions workflow that builds an image and updates one line in that folder — no `terraform apply` involved.

> This repo assumes you're coming from a working GCP/GKE version of this same project. Wherever AWS requires an *extra* step that GKE didn't need, it's called out explicitly.

---

## 2. GCP → AWS Concept Map

| Concept | GCP | AWS | Notes |
|---|---|---|---|
| Compute project boundary | Project (`project_id`) | AWS Account + Region | AWS has no single "project" resource |
| Virtual network | VPC (`google_compute_network`) | VPC (`aws_vpc`) | AWS VPC needs explicit subnets from day 1 |
| Subnetting | Single subnet + secondary IP ranges | Separate public + private subnets per AZ | EKS's VPC-CNI gives pods real VPC IPs directly |
| NAT for private nodes | Cloud Router + Cloud NAT | Internet Gateway + NAT Gateway + Elastic IP | Same job, three AWS resources instead of two |
| Private DB connectivity | VPC Peering (Service Networking) | None needed — RDS ENI lives directly in your subnet | AWS RDS is simpler here |
| Managed Kubernetes | GKE (`google_container_cluster`) | EKS (`aws_eks_cluster`) | GKE bundles a default node pool; EKS keeps them separate |
| Node pool | `google_container_node_pool` | `aws_eks_node_group` | Concept identical |
| Pod-to-cloud-IAM identity | Workload Identity (project-wide pool) | IRSA — per-cluster OIDC provider | **Biggest structural difference** — see Section 13 |
| Ingress / Load balancer | Built-in GCE Ingress controller | AWS Load Balancer Controller (installed via Helm) | On AWS you install your own ingress controller |
| TLS certificate | `ManagedCertificate` CRD | AWS Certificate Manager (ACM) + `certificate-arn` annotation | Both auto-renew |
| Relational database | Cloud SQL | RDS (`aws_db_instance`) | Very close 1:1 mapping |
| Secret storage | Secret Manager | Secrets Manager | Near-identical API shape |
| Container image registry | Artifact Registry | ECR | Same purpose |
| Object storage (backups) | Cloud Storage (GCS) | S3 | Same purpose |
| CI/CD keyless auth | Workload Identity Federation (WIF) | IAM OIDC Identity Provider + `AssumeRoleWithWebIdentity` | Same "no static keys" guarantee |
| Terraform state backend | GCS bucket (built-in locking) | S3 bucket with `use_lockfile = true` (S3 Native State Locking, Terraform 1.10+) | Older AWS setups needed a separate DynamoDB table; not anymore |
| **App deployment mechanism** | **Terraform** (`apps/wordpress` in the original project) | **ArgoCD / GitOps** (`gitops/live-poll-app`, no Terraform) | Deliberate upgrade in this version — see Section 9 |

---

## 3. Architecture

```
 ┌────────────────────┐        ┌───────────────────────────┐
 │   bootstrap/         │──────► │ S3 State Bucket (locking)  │
 │   (run once)         │        │ + GitHub OIDC               │
 └────────────────────┘        └───────────┬───────────────┘
                                            │ used by all pipelines below
                                            ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │                    infra/  (state: eks/prod)                     │
 │   VPC + Subnets + NAT ──► EKS (private nodes) ──► RDS (private)   │
 │        │                                        │                  │
 │        ▼                                        ▼                  │
 │   IAM Roles (cluster/node)               Secrets Manager             │
 │        │                                     (app-db-password)         │
 │        ▼                                                            │
 │   IRSA Roles (needs cluster OIDC) ──► app / alb-controller /         │
 │        │                              external-secrets / backup roles │
 │        ▼                                                            │
 │   ECR (live-poll-app, backup-images)                                │
 └───────────────────────────┬───────────────────────────────────────┘
                              │ outputs read via terraform_remote_state
                              ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │        apps/cluster-addons/  (state: apps/cluster-addons)          │
 │   AWS Load Balancer Controller (Helm)                                │
 │   External Secrets Operator (Helm)                                   │
 │   ArgoCD (Helm) + bootstrap Application CR ──► watches git repo,      │
 │                                                 path gitops/live-poll-app
 └───────────────────────────┬───────────────────────────────────────┘
                              │ from here on, no Terraform touches the app
                              ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │   gitops/live-poll-app/   (plain Kubernetes YAML, no Terraform)    │
 │   Namespace → ServiceAccount(+IRSA) → SecretStore → ExternalSecret │
 │        → Deployment → Service → Ingress(ALB)                        │
 │                                                                       │
 │   ArgoCD continuously reconciles the cluster to match this folder.  │
 └─────────────────────────────────────────────────────────────────┘
```

### CI/CD Flow — Infrastructure (Terraform, unchanged pattern)

```
git push to bootstrap/**, infra/**, or apps/cluster-addons/**
        │
        ▼
Matching GitHub Actions workflow → OIDC → terraform plan/apply
```

### CI/CD Flow — Application (GitOps, new)

```
git push to app/**
        │
        ▼
.github/workflows/build-and-push.yml
        │
        ├── docker build (from app/)
        ├── docker push to ECR (tag = git SHA)
        ├── kustomize edit set image (gitops/live-poll-app/kustomization.yaml)
        └── git commit + push that one-line change
                    │
                    ▼
        ArgoCD (running in-cluster) notices the change on its next
        poll (or webhook) and reconciles the Deployment to the new tag
                    │
                    ▼
        New pods roll out — no terraform apply, no human step
```

---

## 4. Repository Structure

```
eks-infra-terraform/
├── .gitignore
│
├── bootstrap/                      # Terraform Project 1 — run once
│   ├── main.tf iam.tf variables.tf outputs.tf providers.tf versions.tf terraform.tfvars
│
├── infra/                          # Terraform Project 2 — the platform
│   ├── main.tf backend.tf variables.tf outputs.tf providers.tf versions.tf terraform.tfvars
│   └── modules/
│       ├── network/                # VPC, public+private subnets, IGW, NAT
│       ├── iam/                    # cluster role + node role
│       ├── eks/                    # EKS cluster + node group + OIDC provider + addons
│       ├── irsa/                   # workload IAM roles: app, alb-controller, external-secrets, ebs-csi, backup
│       ├── rds/                    # private MySQL instance + random password
│       ├── secrets-manager/        # stores DB password as "app-db-password"
│       ├── ecr/                    # called twice — "live-poll-app" and "backup-images" repos
│       └── backup/                 # S3 bucket for DB backups
│
├── apps/
│   └── cluster-addons/             # Terraform Project 3 — Helm-installed cluster controllers
│       ├── main.tf backend.tf variables.tf outputs.tf providers.tf terraform.tfvars
│       └── modules/
│           ├── alb-controller.tf
│           ├── external-secrets.tf
│           └── argocd.tf           # installs ArgoCD + the bootstrap Application CR
│
├── gitops/live-poll-app/           # NOT a Terraform project — ArgoCD watches this folder
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── serviceaccount.yaml         # IRSA annotation
│   ├── secretstore.yaml            # points at Secrets Manager, contains no secret data
│   ├── externalsecret.yaml         # pulls app-db-password into a local K8s Secret
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
│
├── app/                             # Application source code
│   ├── server.js                    # Express + WebSocket + MySQL
│   ├── package.json
│   ├── Dockerfile
│   └── public/index.html
│
├── backup-job/                     # Docker image + scripts for the DB backup CronJob
│   ├── Dockerfile entrypoint.sh backup.sh restore.sh
│   └── cronjob.yaml restore-job.yaml serviceaccount.yaml
│
└── .github/workflows/
    ├── bootstrap.yml
    ├── infra.yml
    ├── cluster-addons.yml
    ├── build-and-push.yml           # builds/pushes the app image, updates the gitops tag
    └── terraform-infra-destroy.yml
```

---

## 5. Technologies Used

| Category | Tool |
|---|---|
| IaC | Terraform >= 1.10 |
| Cloud | AWS (VPC, EKS, RDS, IAM, Secrets Manager, ECR, S3) |
| Kubernetes distribution | Amazon EKS 1.31 |
| Ingress | AWS Load Balancer Controller |
| Secret sync | External Secrets Operator |
| GitOps / CD | ArgoCD |
| App CI | GitHub Actions (OIDC, no static keys) + Kustomize |
| App | Node.js, Express, `ws` (WebSocket), MySQL 8.0 (RDS) |

---

## 6. Prerequisites

- An AWS account with admin access (to run `bootstrap/` the first time)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.10
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), configured
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) (CI installs its own copy; useful locally too)
- [Docker](https://docs.docker.com/get-docker/) (to build the app image, or let CI do it)
- A domain name you control (for the app's Ingress + ACM certificate) — optional, you can also test over the ALB's raw hostname on plain HTTP
- A GitHub repository to push this code to

You do **not** need `gcloud`, GCP credentials, or a GCP project.

---

## 7. Install Everything

```bash
# 1. Clone
git clone https://github.com/yourusername/eks-infra-terraform.git
cd eks-infra-terraform

# 2. Bootstrap (once, with your real AWS credentials)
cd bootstrap
terraform init && terraform apply
# Copy: terraform_state_bucket, github_actions_role_arn

# 3. Update infra/backend.tf, apps/cluster-addons/backend.tf with your real bucket name
# 4. Update infra/terraform.tfvars with your values

cd ../infra
terraform init && terraform apply
# Copy outputs, especially: cluster_name, vpc_id, app_role_arn, alb_controller_role_arn,
# external_secrets_role_arn, rds_endpoint, ecr_app_repository_url

# 5. Deploy cluster add-ons (ALB Controller + External Secrets + ArgoCD)
cd ../apps/cluster-addons
# put vpc_id and your git repo URL into terraform.tfvars
terraform init
terraform apply -target=helm_release.argocd   # first pass — see Section 14
terraform apply                                 # second pass — creates the Application CR

# 6. Fill in the placeholder values in gitops/live-poll-app/:
#    - serviceaccount.yaml: eks.amazonaws.com/role-arn (from app_role_arn output)
#    - deployment.yaml: DB_HOST (from rds_endpoint output)
#    - ingress.yaml: host + certificate-arn (Section 17), or simplify to plain HTTP
#    Commit and push these changes to main.

# 7. Push any change to app/** (or just push once to trigger the first build)
#    .github/workflows/build-and-push.yml builds the image, pushes to ECR, and
#    updates gitops/live-poll-app/kustomization.yaml automatically.

# 8. ArgoCD picks up the change and deploys the app — no terraform apply needed.
```

From here on: infra/platform changes go through Terraform + PR review; app changes go through a normal `git push` to `app/**`.

---

## 8. Terraform Core Concepts

Unchanged from any other Terraform project — a quick refresher with examples from this codebase:

- **State** — maps `.tf` resources to real AWS resource IDs, stored in S3 (`infra/backend.tf`).
- **Backend** — `backend "s3"` with `use_lockfile = true` (S3 Native State Locking, Terraform 1.10+).
- **Modules** — reusable folders, e.g. `infra/modules/rds`.
- **`terraform_remote_state`** — how `apps/cluster-addons` reads `infra`'s outputs (Section 18).
- **`-target`** — apply just one resource, e.g. `terraform apply -target=helm_release.argocd` (used deliberately in Section 14 to solve a CRD-ordering problem).
- **`terraform state mv` / `-replace`** — rename or force-recreate a resource without editing state by hand.

Note what's **not** in this list anymore: there's no Terraform concept for "how the app gets deployed" — that entire job now belongs to ArgoCD, which has its own reconciliation loop instead of a plan/apply cycle.

---

## 9. Why Split Platform, Add-ons, and App Like This?

Same core reasoning as the GCP original for the first three layers — `bootstrap/` changes once, `infra/` changes rarely and carries the biggest blast radius, `apps/cluster-addons/` changes occasionally (chart version bumps).

The **app layer moving out of Terraform entirely** is this version's one structural upgrade, and it's worth spelling out why:

- **Different change frequency.** Infrastructure changes weekly at most. An application can reasonably change many times a day. Running `terraform plan` against the whole platform every time someone bumps a Docker tag is slow and puts unrelated risk in the same review.
- **Different actor.** Infra changes are usually made by someone comfortable with Terraform and cloud IAM. App changes are made by someone who just wants to ship code — they shouldn't need `terraform` installed, AWS credentials, or state-locking knowledge to deploy a new image.
- **Drift detection for free.** ArgoCD continuously compares the live cluster state to git and will flag (or auto-heal) anything that drifts — `kubectl edit` a Deployment by hand and ArgoCD puts it back. Terraform only checks drift when someone remembers to run `plan`.
- **A clean secrets boundary.** This is the part covered in full in Section 20 — because the app is no longer a Terraform resource, there's no path by which a database password could end up in a `.tfstate` file for the *application* layer at all (RDS's password still lives in `infra/`'s state, which is expected — see that section for the full picture).

---

## 10. Bootstrap

Unchanged in behavior from before. `bootstrap/` creates:

1. **S3 bucket** — versioned, encrypted, public access blocked, with S3 Native State Locking. Stores state for `infra/` and `apps/cluster-addons/`.
2. **GitHub OIDC Identity Provider** — registers `token.actions.githubusercontent.com` as a trusted identity source. Equivalent of GCP's Workload Identity Pool.
3. **GitHub Actions IAM Role** — trust policy restricted to `repo:yourusername/eks-infra-terraform:*`.

Copy outputs into GitHub repo secrets:

| Terraform output | GitHub secret name |
|---|---|
| `github_actions_role_arn` | `AWS_GITHUB_ACTIONS_ROLE_ARN` |
| (your chosen region) | `AWS_REGION` |
| `terraform_state_bucket` | (paste into each `backend.tf`, not a secret) |

---

## 11. Infrastructure (`infra/`)

`infra/main.tf` wires together eight modules:

```
network → iam → eks → irsa → rds
                         │
                 secrets-manager, ecr_app, ecr_backup, backup (independent)
```

Same `network → iam → eks → irsa` ordering constraint as before — IRSA roles trust a specific cluster's OIDC issuer, which only exists once the cluster does. See Section 13.

---

## 12. Module by Module Explanation

### 12.1 `modules/network`
Same as before: VPC, two public + two private subnets across 2 AZs, one NAT Gateway, route tables. No changes for this app.

### 12.2 `modules/iam`
Same: cluster role (assumed by `eks.amazonaws.com`) and node role (assumed by `ec2.amazonaws.com`, mirrors GCP's `node_sa`).

### 12.3 `modules/eks`
Same: cluster, managed node group, OIDC provider, and the EKS add-ons with no IRSA dependency (`vpc-cni`, `coredns`, `kube-proxy`).

### 12.4 `modules/irsa`
Five roles now, one renamed from the original:

| IRSA role | Trusts KSA | Purpose |
|---|---|---|
| `ebs-csi` | `kube-system:ebs-csi-controller-sa` | Kept as a baseline capability; unused by `live-poll-app` itself (no PVC) |
| `app` | `app:app-sa` | Reads `app-db-password` from Secrets Manager (renamed from `wordpress` in the original) |
| `external-secrets` | `external-secrets:external-secrets` | Reads all secrets under this project's prefix |
| `alb-controller` | `kube-system:aws-load-balancer-controller` | Manages ALBs/Target Groups/Security Groups |
| `backup` | `app:rds-backup` | RDS snapshot + S3 bucket + Secrets Manager read access for the backup CronJob |

### 12.5 `modules/rds`
Same shape as before — `aws_db_instance.app`, MySQL 8.0, `gp3`, single-AZ for this demo, private-only, security group scoped to the EKS node security group.

### 12.6 `modules/secrets-manager`
Stores the RDS password as `app-db-password` (renamed from `wordpress-db-password`).

### 12.7 `modules/ecr`
Now called **twice** from `infra/main.tf` — once for `live-poll-app` (the application image) and once for `backup-images` (the backup CronJob image). Each call gets its own repository with the same lifecycle policy (keep last 10 images).

### 12.8 `modules/backup`
Unchanged — an S3 bucket for DB dumps.

---

## 13. IRSA — The AWS Equivalent of Workload Identity

*(Unchanged from before — this section is architecture-level, not app-specific.)*

**On GKE**, Workload Identity uses one project-wide pool (`PROJECT_ID.svc.id.goog`) plus a `google_service_account_iam_member` binding per workload, and a `iam.gke.io/gcp-service-account` annotation on the KSA.

**On EKS**, IRSA uses a per-cluster OIDC provider (created the moment the cluster exists), an IAM trust policy condition matching `system:serviceaccount:<namespace>:<sa-name>`, and an `eks.amazonaws.com/role-arn` annotation on the KSA. Because the OIDC issuer URL only exists after `aws_eks_cluster.primary` finishes creating, `modules/irsa` has a hard dependency on `modules/eks` — this is why the module order here is stricter than GCP's.

The `app` role (Section 12.4) is the direct example: its trust policy only allows `system:serviceaccount:app:app-sa` to assume it — nothing else in the cluster can.

---

## 14. Apps Layer — Cluster Add-ons (incl. ArgoCD)

`apps/cluster-addons/` Helm-installs three controllers:

1. **AWS Load Balancer Controller** — watches `Ingress` objects and provisions ALBs. On GKE this shipped for free; on EKS you install it.
2. **External Secrets Operator** — syncs Kubernetes Secrets from AWS Secrets Manager.
3. **ArgoCD** — the GitOps controller. Once installed, it watches `gitops/live-poll-app` in this repo and keeps the cluster's actual state matching whatever is committed there.

Along with ArgoCD itself, this module creates one `kubernetes_manifest` resource: an ArgoCD **`Application`** object that tells ArgoCD *what* to watch (this repo, this branch, the `gitops/live-poll-app` path) and *where* to deploy it (the `app` namespace). This `Application` object is the **only** app-deployment-related thing Terraform ever touches — it's a pointer, not the application itself.

**A real ordering quirk you'll hit on the first apply**: the `Application` object's Kubernetes API kind (`argoproj.io/v1alpha1 Application`) is a Custom Resource Definition that ArgoCD's own Helm chart installs. Terraform's `kubernetes_manifest` resource needs that CRD to already exist in the cluster's schema at *plan* time, but on a from-scratch apply, the Helm release that installs the CRD and the manifest that uses it are in the same `terraform apply`. The fix is a two-pass apply, which is called out directly in `apps/cluster-addons/modules/argocd.tf`:

```bash
terraform apply -target=helm_release.argocd
terraform apply
```

This is a general Terraform + CRD ordering issue, not something specific to ArgoCD — you'll see the same pattern any time a single apply both installs a CRD and creates a resource of that CRD's kind.

---

## 15. The Application — `live-poll-app`

A deliberately small Node.js app (`app/`) that demonstrates the exact same DB + secrets pattern WordPress did, with two simplifications: no file uploads (so no PVC/EBS complexity at all), and a genuinely real-time element (a WebSocket broadcast) so "real-time app" isn't just a label.

- **`server.js`** — Express serves a static frontend and a small REST API (`GET /api/results`, `POST /api/vote/:id`); a `ws` WebSocket server pushes updated vote counts to every connected browser the instant a vote lands; `mysql2` talks to RDS.
- **`public/index.html`** — a single page with three buttons and live-updating bars, connected over `ws://.../ws`.
- **Configuration** — everything the app needs comes from environment variables: `DB_HOST`, `DB_NAME`, `DB_USER` (plain values, fine to be visible in the Deployment spec) and `DB_PASSWORD` (from a Kubernetes Secret — never a plain value, see Section 20).
- **`Dockerfile`** — a small `node:20-alpine` image, runs as the non-root `node` user.

This is intentionally the *only* piece of the entire repository that a typical "I just want to ship a feature" developer needs to touch day to day.

---

## 16. GitOps — `gitops/live-poll-app`

This folder is **not** a Terraform project — there's no `.tf` file in it, no state, no provider block. It's plain Kubernetes YAML, tied together with a `kustomization.yaml`, and ArgoCD is the only thing that ever applies it to the cluster.

- **`namespace.yaml`** — the `app` namespace.
- **`serviceaccount.yaml`** — `app-sa`, annotated with the `app` IRSA role's ARN (from `infra`'s `app_role_arn` output — copied in once, manually, the same way every other placeholder ARN in this repo is filled in after `infra` applies).
- **`secretstore.yaml`** — points External Secrets Operator at AWS Secrets Manager, authenticating via `app-sa`'s IRSA identity. Contains no secret material — safe to commit, safe to make this repo public.
- **`externalsecret.yaml`** — a pointer: "fetch `app-db-password` from Secrets Manager, put it in a local Secret called `app-db-credentials`." Also contains no secret material.
- **`deployment.yaml`** — the actual app, reading `DB_PASSWORD` from the `app-db-credentials` Secret that External Secrets Operator creates at runtime.
- **`service.yaml`** / **`ingress.yaml`** — plain `ClusterIP` Service + ALB Ingress, same annotation pattern used everywhere else in this repo.
- **`kustomization.yaml`** — the one file that changes on every single app deploy. `.github/workflows/build-and-push.yml` runs `kustomize edit set image` on it after every successful build, which is a one-line change to the `newTag` value, then commits it. ArgoCD notices the commit and rolls out the new image.

---

## 17. ACM Certificate & Domain Setup

Same process as any ALB-based Ingress on AWS — request the cert before creating the Ingress:

```bash
aws acm request-certificate \
  --domain-name poll.example.com \
  --validation-method DNS \
  --region ap-south-1
```

Fetch the DNS validation record and create the CNAME in your DNS provider:

```bash
aws acm describe-certificate \
  --certificate-arn <the-arn> \
  --region ap-south-1 \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord"
```

Once `Status` is `ISSUED`, paste the ARN into `gitops/live-poll-app/ingress.yaml`'s `certificate-arn` annotation and the `host` field, commit, and let ArgoCD roll it out. If you'd rather skip TLS for a first test, delete the two `ssl-`/`certificate-arn` annotations and the `443` listener entry, and just hit the ALB's own hostname over plain HTTP.

Get the ALB hostname:

```bash
kubectl get ingress -n app
```

---

## 18. Reading Data Across Projects — `terraform_remote_state`

```hcl
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "eks-prod-demo-001-tf-state"
    key    = "eks/prod/terraform.tfstate"
    region = "ap-south-1"
  }
}
```

`apps/cluster-addons/main.tf` uses this to read `alb_controller_role_arn` and `external_secrets_role_arn`. Notice what it does **not** read: `app_role_arn` and `rds_endpoint` are consumed by `gitops/live-poll-app`'s plain YAML files instead, filled in manually once (Section 16) — because that folder has no Terraform provider block to run a `data` lookup with in the first place. This is one of the clearest illustrations of the boundary in this repo: **`terraform_remote_state` is how Terraform projects talk to each other; plain values pasted into YAML are how the GitOps layer receives what it needs from Terraform.**

---

## 19. GitHub Actions + OIDC

Every Terraform-driving workflow (`infra.yml`, `cluster-addons.yml`, `terraform-infra-destroy.yml`) authenticates the same way:

```yaml
permissions:
  id-token: write

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_GITHUB_ACTIONS_ROLE_ARN }}
      aws-region: ${{ secrets.AWS_REGION }}
```

`build-and-push.yml` is different in one respect worth noticing: it also needs `permissions: contents: write`, because after pushing the image it commits the updated tag back into the repo itself. It still uses the exact same OIDC role for its AWS calls (just to push to ECR) — see Section 20 for exactly what that role can and can't touch.

Required GitHub repository secrets:

| Secret | Value |
|---|---|
| `AWS_GITHUB_ACTIONS_ROLE_ARN` | `bootstrap` output `github_actions_role_arn` |
| `AWS_REGION` | e.g. `ap-south-1` |
| `AWS_BOOTSTRAP_ACCESS_KEY_ID` / `AWS_BOOTSTRAP_SECRET_ACCESS_KEY` | only for the one-time `bootstrap.yml` run; delete after |

---

## 20. Secret Management: Terraform vs GitHub Actions vs ArgoCD

This is the question this version of the repo was specifically restructured to answer clearly. There is exactly **one** real secret value anywhere in this system — the RDS password — and it's worth tracing everywhere it does, and does not, go.

### Where the password is *born*

```hcl
# infra/modules/rds/password.tf
resource "random_password" "db_password" {
  length  = 24
  special = true
}
```

Terraform generates this value. It is written to `infra`'s **state file** (in the S3 bucket from `bootstrap/`) and to the **RDS instance itself**. That state file is the one place in this entire system where the raw password is unavoidably present at rest — which is exactly why that S3 bucket is encrypted, versioned, and has public access fully blocked (Section 21), and why nobody should ever be routinely reading `infra`'s `terraform.tfstate` by hand.

### Where Terraform puts it next — and stops

```hcl
# infra/modules/secrets-manager/main.tf
resource "aws_secretsmanager_secret_version" "app_db_password" {
  secret_id     = aws_secretsmanager_secret.app_db_password.id
  secret_string = var.db_password
}
```

Terraform writes the password into AWS Secrets Manager, under the name `app-db-password`. **This is the last Terraform resource that ever touches the raw value.** No other `.tf` file in `infra/`, and nothing at all in `apps/cluster-addons/`, ever reads it back out.

### Where GitHub Actions stands — deliberately outside this path entirely

Neither `infra.yml` nor `build-and-push.yml` ever requests, reads, or has permission to read `app-db-password`. Check the IAM policy in `bootstrap/iam.tf`: it's broad (flagged in Section 28 as a learning-project simplification), but even if it were tightened down to exactly what each workflow needs, `build-and-push.yml`'s job would need **zero** Secrets Manager permissions — it only builds a Docker image and pushes it to ECR. The application never receives its DB password *from* CI; it receives it *from Kubernetes*, at pod start time, from a Secret that CI never created and can't read.

### Where ArgoCD stands — it applies pointers, never values

Everything ArgoCD applies from `gitops/live-poll-app/` is plain YAML committed to git:

```yaml
# gitops/live-poll-app/externalsecret.yaml — safe to make this repo public
spec:
  data:
    - secretKey: password
      remoteRef:
        key: app-db-password   # <- a *name*, not a value
```

ArgoCD's job is to make sure this `ExternalSecret` object (and the `Deployment` that references the Secret it produces) exist in the cluster, matching git. ArgoCD itself never fetches the actual password from Secrets Manager — it doesn't even have IAM permissions to. That's a separate controller's job entirely:

### Who actually fetches the value — the External Secrets Operator, using IRSA

```yaml
# gitops/live-poll-app/secretstore.yaml
spec:
  provider:
    aws:
      service: SecretsManager
      auth:
        jwt:
          serviceAccountRef:
            name: app-sa   # <- IRSA identity, not a static credential
```

The External Secrets Operator pod (installed by Terraform in `apps/cluster-addons`, IRSA role also created by Terraform in `infra/modules/irsa`) is the **only** component in this entire system, other than Terraform itself at creation time, that ever calls `secretsmanager:GetSecretValue` on `app-db-password`. It does so using temporary STS credentials obtained via the `app-sa` ServiceAccount's IRSA identity — no static AWS key exists anywhere in this step either.

### The full path, end to end

```
Terraform (infra/)
    generates password → writes to RDS → writes to Secrets Manager
    [ raw value touches: Terraform state, RDS, Secrets Manager — nothing else ]

GitHub Actions (build-and-push.yml)
    builds image → pushes to ECR → edits an image *tag* in git
    [ never requests, never receives, never could receive the password ]

ArgoCD (in-cluster)
    applies gitops/live-poll-app/*.yaml to the cluster
    [ applies pointer objects only — SecretStore, ExternalSecret, Deployment ]

External Secrets Operator (in-cluster, IRSA)
    reads Secrets Manager using app-sa's temporary IRSA credentials
    writes the value into a local Kubernetes Secret (app-db-credentials)
    [ this is the only runtime read of the actual password ]

live-poll-app pod
    reads DB_PASSWORD from the app-db-credentials Secret's env mapping
    [ the only component that ever needs the plaintext value to do its job ]
```

**The one-sentence version**: Terraform creates the secret, External Secrets Operator (via IRSA, no static keys) is the only thing that ever reads it back out at runtime, and both GitHub Actions and ArgoCD only ever handle *pointers* to it — never the value itself. This is precisely why it's safe for `gitops/live-poll-app/` to be a public GitHub repo even though it fully describes how the app gets its database credentials.

---

## 21. Terraform Backend

```hcl
terraform {
  backend "s3" {
    bucket       = "eks-prod-demo-001-tf-state"
    key          = "eks/prod/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

`use_lockfile = true` turns on S3 Native State Locking (Terraform 1.10+) — no separate DynamoDB table needed.

---

## 22. State File

Never edit `.tfstate` by hand, never commit it to git, never run concurrent applies against the same `key` outside the locking mechanism. If a lock ever gets stuck:

```bash
terraform force-unlock <LOCK_ID>
```

---

## 23. Deployment Walkthrough

### Step 1 — Bootstrap
```bash
cd bootstrap && terraform init && terraform apply
```
Update `backend.tf` in `infra/` and `apps/cluster-addons/` with the real bucket name. Add GitHub secrets (Section 19).

### Step 2 — Infra
```bash
cd ../infra && terraform init && terraform apply
```
~15-20 minutes. Configure kubectl:
```bash
aws eks update-kubeconfig --name prod-eks-cluster --region ap-south-1
kubectl get nodes
```

### Step 3 — Cluster Add-ons (ALB Controller, External Secrets, ArgoCD)
```bash
cd ../apps/cluster-addons
# fill in vpc_id and git_repo_url in terraform.tfvars
terraform init
terraform apply -target=helm_release.argocd   # first pass, see Section 14
terraform apply                                 # second pass
```

### Step 4 — Wire up the placeholders in `gitops/live-poll-app/`
Fill in `serviceaccount.yaml`'s role ARN and `deployment.yaml`'s `DB_HOST` from `infra`'s outputs, and (optionally) `ingress.yaml`'s domain/cert ARN (Section 17). Commit and push to `main`.

### Step 5 — Trigger the first app build
Push any change under `app/**` (or re-run `build-and-push.yml` manually via `workflow_dispatch`). This builds and pushes the image and updates the tag in git.

### Step 6 — Watch ArgoCD deploy it
```bash
kubectl get application -n argocd
kubectl get pods -n app
kubectl get ingress -n app
```

Visit the ALB hostname (or your domain, once DNS is pointed at it).

---

## 24. Verification Commands

```bash
# Cluster
kubectl get nodes -o wide
kubectl get pods -A

# ArgoCD
kubectl get application -n argocd
kubectl -n argocd get pods
# Access the ArgoCD UI locally:
kubectl -n argocd port-forward svc/argocd-server 8080:80
# then open http://localhost:8080 (see cluster-addons output "argocd_release" for the release name)

# App
kubectl get pods -n app
kubectl logs -n app deploy/live-poll-app
kubectl describe ingress live-poll-app -n app

# Secrets synced correctly?
kubectl get externalsecret -n app
kubectl get secret app-db-credentials -n app -o jsonpath='{.data.password}' | base64 -d

# RDS reachable from a debug pod?
kubectl run mysql-client --rm -it --image=mysql:8.0 -n app -- \
  mysql -h <rds_endpoint> -u pollapp -p

# ALB provisioned?
aws elbv2 describe-load-balancers --query "LoadBalancers[*].DNSName"
```

---

## 25. Backup & Restore

`backup-job/` runs a daily CronJob that reads the DB password from Secrets Manager (via its own dedicated `backup` IRSA role, not the app's) and `mysqldump`s the database to the S3 backup bucket. Unlike the earlier WordPress version, there's no uploads folder to also archive — `live-poll-app` keeps all of its state in RDS.

```bash
cd backup-job
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-south-1.amazonaws.com

docker build -t <ecr_backup_repository_url>:v1 .
docker push <ecr_backup_repository_url>:v1
```

Fill in the placeholders in `serviceaccount.yaml` and `cronjob.yaml` (role ARN, image URL, RDS endpoint), then:

```bash
kubectl apply -f backup-job/serviceaccount.yaml
kubectl apply -f backup-job/cronjob.yaml
```

Restore a specific date:

```bash
# edit restore-job.yaml's MODE/date if needed, then:
kubectl apply -f backup-job/restore-job.yaml
```

Note this folder is applied with plain `kubectl apply`, not ArgoCD — it's an operational tool, not part of the app's desired state, so it's kept out of the GitOps loop deliberately.

---

## 26. Destroy Walkthrough

Destroy in reverse order. Because the app is managed by ArgoCD, delete the `Application` object (or just let `cluster-addons`'s destroy remove it) **before** destroying `infra/`, so ArgoCD doesn't try to reconcile against a cluster that's disappearing mid-destroy:

```bash
kubectl delete application live-poll-app -n argocd --wait=true

cd apps/cluster-addons && terraform destroy
cd ../../infra              && terraform destroy
cd ../bootstrap                && terraform destroy   # only for a full teardown
```

Or trigger `.github/workflows/terraform-infra-destroy.yml` manually, typing `DESTROY` to confirm — it only destroys `infra/`, so remove the ArgoCD `Application` and run `apps/cluster-addons`'s destroy yourself first.

`skip_final_snapshot = true` on RDS means this deletes your database with no final snapshot — fine for a learning project, change it for real data.

---

## 27. Cost Estimation

Rough monthly estimate for `ap-south-1`, 24/7:

| Resource | Approx. monthly cost |
|---|---|
| EKS control plane | ~$73 |
| 2x `t3.medium` worker nodes | ~$60 |
| NAT Gateway (1x) | ~$33 + data processing |
| RDS `db.t3.medium` (single-AZ) | ~$55 |
| ALB | ~$20 + LCU usage |
| S3 + Secrets Manager + ECR (x2 repos) | a few dollars |
| **Total** | **~$245-270/month** |

Slightly lower than the WordPress version, since there's no EBS volume cost — `live-poll-app` has no PVC. **Destroy the stack when you're not using it.**

---

## 28. Security Best Practices

- `bootstrap/iam.tf` attaches `AdministratorAccess` to the GitHub Actions role for simplicity — flagged in the code itself. Scope this down for real production use, and note from Section 20 that `build-and-push.yml` specifically needs no Secrets Manager access at all — a good first target for tightening.
- RDS is never publicly accessible; its security group only allows the EKS node security group on port 3306.
- Every IRSA role in `modules/irsa` is scoped to one specific `namespace:serviceaccount` pair.
- `build-and-push.yml` has `contents: write` — it can push commits to this repo. Branch protection rules on `main` (require PR review) are a reasonable guard if you don't want CI committing directly, at the cost of needing a manual merge step before ArgoCD picks up a new image.
- ArgoCD's own UI/API (`argocd-server`) is left as `ClusterIP` in this repo deliberately, reachable only via `kubectl port-forward` — exposing it externally needs its own Ingress, TLS, and an authentication decision (SSO, or at minimum changing the default admin password) that's outside this repo's scope.
- `skip_final_snapshot = true` and `deletion_protection = false` on RDS are learning-project conveniences — change both before running this against real data.

---

## 29. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `terraform apply` in `apps/cluster-addons` fails with "no matches for kind Application" | First-ever apply, CRD not registered yet | Run `terraform apply -target=helm_release.argocd` first, then `terraform apply` again (Section 14) |
| ArgoCD shows the app `OutOfSync` forever | A manifest in `gitops/live-poll-app` has a placeholder value still in it (e.g. `REPLACE_WITH_RDS_ENDPOINT`) | Fill in the real values from `infra`'s outputs, commit, push |
| ArgoCD shows `Missing` for the Deployment | `kustomization.yaml`'s image tag doesn't exist in ECR yet | Trigger `build-and-push.yml` at least once |
| Pod stuck `CrashLoopBackOff` | Usually a DB connection issue | `kubectl logs -n app deploy/live-poll-app`; check `DB_HOST` value and that the `app-db-credentials` Secret actually synced (`kubectl get externalsecret -n app`) |
| `ExternalSecret` not syncing | IRSA role trust condition mismatch, or wrong region in `secretstore.yaml` | `kubectl describe externalsecret -n app`; verify `system:serviceaccount:app:app-sa` matches the trust policy in `infra/modules/irsa/app.tf` |
| `build-and-push.yml` fails to push the git commit | `contents: write` permission missing, or branch protection blocking direct pushes | Check workflow `permissions:` block; if branch protection is on, switch to opening a PR instead of pushing directly |
| Ingress has no address | AWS Load Balancer Controller not running, or wrong subnet tags | `kubectl logs -n kube-system deploy/aws-load-balancer-controller` |
| `terraform apply` hangs on state lock | A previous run died mid-apply, left an S3 lock file | Confirm no apply is running, then `terraform force-unlock <ID>` |

---

## 30. FAQ

**Q: Why does the first `apps/cluster-addons` apply need two passes?**
A: Terraform's `kubernetes_manifest` resource needs the target CRD to already exist in the cluster's API schema when it plans. Since the same apply both installs ArgoCD (which brings the CRD) and creates an `Application` object (which uses that CRD), the very first run needs `-target=helm_release.argocd` first. Every apply after that works normally in one pass.

**Q: Could I have Terraform apply `gitops/live-poll-app/*.yaml` directly instead of using ArgoCD?**
A: Yes, and that's exactly what the earlier WordPress version of this repo did. The tradeoff is in Section 9 — you'd get back a single reviewable `terraform plan` for the whole platform, at the cost of coupling app deploy speed to Terraform's plan/apply cycle and losing continuous drift detection.

**Q: Why does `build-and-push.yml` commit back to the repo instead of using something like ArgoCD Image Updater?**
A: Committing the tag change keeps the entire desired state of the cluster visible in one place — `git log` on `gitops/live-poll-app/kustomization.yaml` is a complete deploy history. ArgoCD Image Updater (a separate, optional ArgoCD component) can automate this same step without a commit, at the cost of that history living in ArgoCD instead of git. Both are legitimate GitOps patterns — Section 32 covers this as a possible improvement.

**Q: Why does the backup CronJob use `kubectl apply` instead of also being managed by ArgoCD?**
A: It's an operational, on-demand tool (you run a restore job manually when you need one), not part of the app's continuously-reconciled desired state — a reasonable line to draw between "what ArgoCD owns" and "what an operator runs by hand."

---

## 31. Interview Questions

1. Trace the RDS password from the moment `random_password.db_password` is created to the moment `live-poll-app`'s Node.js process reads `process.env.DB_PASSWORD`. Name every component that touches the raw value along the way, and every component that only ever touches a *pointer* to it.
2. Why does `apps/cluster-addons`'s first-ever `terraform apply` need to be run twice?
3. What's the practical difference between what `terraform_remote_state` gives `apps/cluster-addons` and what plain YAML placeholder-filling gives `gitops/live-poll-app`? Why can't the latter just use `terraform_remote_state` too?
4. If someone ran `kubectl scale deploy/live-poll-app --replicas=10` by hand, what would ArgoCD do about it, and why does Terraform not have an equivalent behavior?
5. Why does `build-and-push.yml`'s IAM role never need any Secrets Manager permission, even though it's building and deploying an app that needs a database password?
6. What actually breaks if `gitops/live-poll-app/serviceaccount.yaml`'s role ARN doesn't match the trust policy created in `infra/modules/irsa/app.tf`?

---

## 32. Future Improvements

- ArgoCD Image Updater instead of the CI-commits-a-tag pattern, to remove the "bot commit" from git history
- ArgoCD `AppProject` with RBAC, instead of the default project, once there's more than one application
- Multi-AZ RDS + read replica
- Horizontal Pod Autoscaler for `live-poll-app`
- One NAT Gateway per AZ instead of a single one
- An Ingress + TLS + SSO in front of the ArgoCD UI itself, if the team needs it reachable outside `kubectl port-forward`
- Sealed Secrets or SOPS as an alternative to External Secrets Operator, if you ever need to author secret *references* differently
- Terraform `Sentinel`/`OPA` policy checks in CI before `apply`, and `kubeval`/`conftest` checks on `gitops/live-poll-app` manifests before ArgoCD syncs them
