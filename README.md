# eks-infra-terraform — Multi-Account AWS Platform (Terraform)

This repo owns **infrastructure only** — VPC, EKS, RDS, IAM/IRSA, Secrets Manager, ECR, and the cluster add-ons (AWS Load Balancer Controller, External Secrets Operator, ArgoCD). It contains **no application code and no Kubernetes Deployment for the app itself** — that lives in a separate repo, [`live-poll-app`](#companion-repo), which ArgoCD deploys independently of anything in this repo.

It's also structured for **two separate AWS accounts** — a dev/test account and a production account — each with its own complete, independent copy of the platform: its own VPC, its own EKS cluster, its own RDS database, its own ArgoCD instance. Nothing is shared between them except the Terraform module code.

---

## Table of Contents

1. [Two Repos, Two Accounts — the Big Picture](#1-two-repos-two-accounts--the-big-picture)
2. [Repository Structure](#2-repository-structure)
3. [How Environments Are Isolated](#3-how-environments-are-isolated)
4. [GitHub Environments Setup](#4-github-environments-setup)
5. [First-Time Setup, Per Account](#5-first-time-setup-per-account)
6. [The Two-Pass Apply (ArgoCD CRD Ordering)](#6-the-two-pass-apply-argocd-crd-ordering)
7. [Module by Module](#7-module-by-module)
8. [IRSA](#8-irsa)
9. [Dev vs Prod Sizing Differences](#9-dev-vs-prod-sizing-differences)
10. [Verification Commands](#10-verification-commands)
11. [Backup & Restore](#11-backup--restore)
12. [Destroy Walkthrough](#12-destroy-walkthrough)
13. [Cost Estimation](#13-cost-estimation)
14. [Security Best Practices](#14-security-best-practices)
15. [Troubleshooting](#15-troubleshooting)
16. [FAQ](#16-faq)

---

## 1. Two Repos, Two Accounts — the Big Picture

```
                    ┌───────────────────────────┐
                    │   live-poll-app  (repo 2)   │
                    │   app/ + gitops/base+overlays │
                    │   NO Terraform in this repo    │
                    └──────────┬─────────────┬────┘
                               │             │
                    watches    │             │  watches
              gitops/overlays/dev   gitops/overlays/prod
                               │             │
   ┌───────────────────────────┘             └───────────────────────────┐
   ▼                                                                       ▼
┌─────────────────────────────────┐                     ┌─────────────────────────────────┐
│         DEV/TEST AWS ACCOUNT       │                     │           PROD AWS ACCOUNT          │
│                                     │                     │                                     │
│  bootstrap/envs/dev                │                     │  bootstrap/envs/prod                │
│      → S3 state bucket + OIDC role │                     │      → S3 state bucket + OIDC role │
│                                     │                     │                                     │
│  infra/envs/dev                    │                     │  infra/envs/prod                    │
│      → VPC, EKS, RDS (micro,        │                     │      → VPC, EKS, RDS (medium,       │
│         single-AZ), IRSA, ECR, S3    │                     │         Multi-AZ), IRSA, ECR, S3   │
│                                     │                     │                                     │
│  apps/cluster-addons/envs/dev       │                     │  apps/cluster-addons/envs/prod       │
│      → ALB Controller, External     │                     │      → ALB Controller, External     │
│         Secrets, ArgoCD             │                     │         Secrets, ArgoCD             │
│         (watches gitops/overlays/dev)│                    │         (watches gitops/overlays/prod)│
└─────────────────────────────────┘                     └─────────────────────────────────┘
```

**This repo (`eks-infra-terraform`)** is applied twice — once against each AWS account, from `envs/dev` and `envs/prod` respectively. **The other repo (`live-poll-app`)** is applied zero times by Terraform — it's pure GitOps, and its `gitops/overlays/dev` and `gitops/overlays/prod` folders are what each account's ArgoCD instance independently watches.

Why split this way instead of one repo with everything: a person doing app work never needs to clone this repo, install Terraform, or hold any AWS credential at all. A person doing platform work (this repo) never needs to touch application code or worry about breaking a Docker build. Each side's CI has exactly the permissions its job needs and nothing more — see `live-poll-app`'s README for the secret-flow trace all the way down to the database password.

---

## 2. Repository Structure

```
eks-infra-terraform/
├── .gitignore
│
├── bootstrap/
│   ├── modules/core/                # shared: S3 state bucket + GitHub OIDC provider + role
│   └── envs/
│       ├── dev/    main.tf backend(none-local) providers.tf variables.tf outputs.tf terraform.tfvars
│       └── prod/   (same shape, prod account values)
│
├── infra/
│   ├── modules/                     # shared, unchanged by environment
│   │   ├── network/ iam/ eks/ irsa/ rds/ secrets-manager/ ecr/ backup/
│   └── envs/
│       ├── dev/     main.tf backend.tf providers.tf variables.tf outputs.tf terraform.tfvars
│       └── prod/    (same shape, different backend bucket + tfvars + RDS sizing)
│
├── apps/cluster-addons/
│   ├── modules/                     # shared: alb-controller.tf, external-secrets.tf, argocd.tf
│   └── envs/
│       ├── dev/     main.tf backend.tf providers.tf variables.tf outputs.tf terraform.tfvars
│       └── prod/    (same shape, watches gitops/overlays/prod instead of .../dev)
│
├── backup-job/                       # Docker image + kubectl-applied manifests (not GitOps-managed)
│   ├── Dockerfile entrypoint.sh backup.sh restore.sh
│   └── cronjob.yaml restore-job.yaml serviceaccount.yaml
│
└── .github/workflows/
    ├── _terraform-apply.yml          # reusable — actual terraform init/plan/apply logic, once
    ├── bootstrap-dev.yml  bootstrap-prod.yml
    ├── infra-dev.yml       infra-prod.yml
    ├── cluster-addons-dev.yml  cluster-addons-prod.yml
    └── destroy-dev.yml     destroy-prod.yml
```

Every `envs/<env>` folder is a genuine, independent Terraform root module — its own state, its own backend, its own provider block. The only thing shared between `dev` and `prod` is the module *code* under `modules/`, never any state or any live resource.

---

## 3. How Environments Are Isolated

| Layer | Dev/Test | Prod |
|---|---|---|
| AWS Account | Account A (yours) | Account B (yours) |
| State bucket | `eks-dev-001-tf-state` | `eks-prod-001-tf-state` |
| EKS cluster name | `dev-eks-cluster` | `prod-eks-cluster` |
| Node sizing | `t3.small`, 1-3 nodes | `t3.medium`, 2-6 nodes |
| RDS sizing | `db.t3.micro`, single-AZ | `db.t3.medium`, Multi-AZ |
| RDS deletion protection | off | on |
| ArgoCD watches | `gitops/overlays/dev` (in `live-poll-app`) | `gitops/overlays/prod` |
| GitHub Environment | `dev` | `prod` |
| Deploy trigger | automatic, every push | manual promotion only |

Because dev and prod are **different AWS accounts** (not just different regions or a naming convention within one account), there is no IAM policy, no VPC peering, and no shared resource that could let a mistake in one account touch the other. This is the strongest form of environment isolation available on AWS — stronger than using one account with a `dev-` / `prod-` prefix on everything, which is a common but weaker pattern (all it takes there is one over-broad IAM policy to break the isolation).

---

## 4. GitHub Environments Setup

Create two GitHub Environments under **Settings → Environments**: `dev` and `prod`. Each needs its own secrets — GitHub automatically scopes `secrets.X` to whichever environment a job declares with `environment: <name>`, so the same secret *name* (`AWS_ROLE_ARN`) safely holds two different values depending on which workflow is running.

| Secret (per environment) | dev value | prod value |
|---|---|---|
| `AWS_ROLE_ARN` | dev account's `github_actions_role_arn` output | prod account's `github_actions_role_arn` output |
| `AWS_REGION` | e.g. `ap-south-1` | e.g. `ap-south-1` |
| `AWS_BOOTSTRAP_ACCESS_KEY_ID` / `AWS_BOOTSTRAP_SECRET_ACCESS_KEY` | one-time, dev account IAM user | one-time, prod account IAM user |

For a real approval gate before anything touches production, go to **Settings → Environments → prod → Required reviewers** and add at least one person — every `*-prod.yml` workflow will then pause for approval before it runs.

---

## 5. First-Time Setup, Per Account

Repeat this once for the dev account, once for the prod account (swap `dev` for `prod` throughout):

```bash
# 1. Bootstrap — run locally with real AWS credentials for that account
#    (or via bootstrap-dev.yml with one-time static keys, see Section 4)
cd bootstrap/envs/dev
terraform init && terraform apply
# copy: terraform_state_bucket, github_actions_role_arn

# 2. Add the GitHub Environment secrets (Section 4) for this environment

# 3. infra/envs/dev/backend.tf and terraform.tfvars already assume the
#    naming convention "eks-dev-001-*" — change the bucket name here if
#    your bootstrap output differs
cd ../../../infra/envs/dev
terraform init && terraform apply
# copy: cluster_name, vpc_id, app_role_arn, alb_controller_role_arn,
#       external_secrets_role_arn, rds_endpoint, ecr_app_repository_url

# 4. Cluster add-ons (ALB Controller, External Secrets, ArgoCD)
cd ../../apps/cluster-addons/envs/dev
# fill in vpc_id and git_repo_url (pointing at the live-poll-app repo) in terraform.tfvars
terraform init
terraform apply -target=module.cluster_addons.helm_release.argocd   # first pass, see Section 6
terraform apply                                                        # second pass

# 5. Go fill in the placeholders in live-poll-app's gitops/overlays/dev/
#    (role ARN, RDS endpoint, ECR URL, ACM cert) using the outputs from
#    steps 3-4, and push the first app build — see that repo's README.
```

---

## 6. The Two-Pass Apply (ArgoCD CRD Ordering)

`apps/cluster-addons/envs/<env>`'s very first `terraform apply` needs two passes, every time, in either account:

```bash
terraform apply -target=module.cluster_addons.helm_release.argocd
terraform apply
```

Why: the ArgoCD Helm chart installs the `Application` Custom Resource Definition, and Terraform's `kubernetes_manifest` resource (used to create the bootstrap `Application` object that tells ArgoCD what to watch) needs that CRD to already exist in the cluster's API schema *at plan time*. Since both things are in the same `terraform apply` on a from-scratch environment, the first pass installs just the Helm release (and the CRD with it), and the second pass can then successfully plan and create the `Application` object. Every apply after that works in a single pass, because the CRD already exists.

The CI workflows (`cluster-addons-dev.yml` / `cluster-addons-prod.yml`) already do this automatically via the `extra_target` input — you only need to think about the two-pass manually if you're running `terraform apply` by hand.

---

## 7. Module by Module

Unchanged in behavior from a single-account setup — each module is just invoked twice now, once per environment, with different input values.

- **`network`** — VPC, 2 public + 2 private subnets, 1 NAT Gateway. Independent VPC per account (no peering between dev and prod — there's no reason for one).
- **`iam`** — cluster role + node role, one set per account.
- **`eks`** — cluster, managed node group, OIDC provider, baseline add-ons (`vpc-cni`, `coredns`, `kube-proxy`).
- **`irsa`** — `ebs-csi`, `app`, `external-secrets`, `alb-controller`, `backup` roles. Each account's IRSA roles trust *that account's own* cluster OIDC provider — a role in the dev account has no meaning in the prod account and vice versa.
- **`rds`** — now takes `instance_class`, `allocated_storage`, `multi_az`, `backup_retention_period`, `skip_final_snapshot`, and `deletion_protection` as inputs (previously hardcoded), specifically so `infra/envs/dev` and `infra/envs/prod` can pass genuinely different values — see Section 9.
- **`secrets-manager`** — stores `app-db-password`, one independent secret per account.
- **`ecr`** — called twice per account (`live-poll-app`, `backup-images`) — four repositories total across both accounts, none shared.
- **`backup`** — one S3 bucket per account.

---

## 8. IRSA

Same mechanism as a single-account setup (see the module comments in `infra/modules/irsa/*.tf` for the full explanation of how IRSA replaces GKE's Workload Identity) — the only change here is that it now happens twice, completely independently, once per AWS account. A pod in the dev cluster can only ever assume a role that dev's own OIDC provider is trusted by; there's no cross-account trust configured anywhere in this repo, deliberately.

---

## 9. Dev vs Prod Sizing Differences

| Setting | Dev/Test | Prod | Where it's set |
|---|---|---|---|
| EKS node instance type | `t3.small` | `t3.medium` | `infra/envs/<env>/terraform.tfvars` |
| EKS node count | 1 desired, 1-3 range | 2 desired, 2-6 range | `infra/envs/<env>/main.tf` |
| RDS instance class | `db.t3.micro` | `db.t3.medium` | `infra/envs/<env>/main.tf` (`module.rds` block) |
| RDS storage | 20 GB | 50 GB | same |
| RDS Multi-AZ | off | on | same |
| RDS backup retention | 3 days | 14 days | same |
| RDS final snapshot on destroy | skipped | taken (named with a timestamp) | same |
| RDS deletion protection | off | on | same |

All of this is driven by explicit values passed into shared modules — nothing in `infra/modules/rds` or `infra/modules/eks` itself knows or cares which environment is calling it. If you ever want a third environment (say, `staging`), you'd copy an `envs/dev`-shaped folder, point its backend at a third AWS account (or a third state key, if you'd rather share an account), and choose sizing values somewhere between the two examples here.

---

## 10. Verification Commands

Run against whichever account's kubeconfig you've configured (`aws eks update-kubeconfig --name dev-eks-cluster` or `--name prod-eks-cluster`):

```bash
kubectl get nodes -o wide
kubectl get application -n argocd
kubectl get pods -n app
kubectl get externalsecret -n app
aws elbv2 describe-load-balancers --query "LoadBalancers[*].DNSName"
```

---

## 11. Backup & Restore

`backup-job/` is applied with plain `kubectl apply`, independently in each cluster — it is deliberately outside the GitOps loop (it's an operational tool, not part of the app's desired state). Build and push its image to *each* account's own `backup-images` ECR repo:

```bash
cd backup-job
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-south-1.amazonaws.com
docker build -t <ecr_backup_repository_url>:v1 .
docker push <ecr_backup_repository_url>:v1
```

Fill in the per-account placeholders in `serviceaccount.yaml` and `cronjob.yaml`, then `kubectl apply -f backup-job/` against that account's cluster. Repeat separately for dev and prod — there is no shared backup infrastructure between the two accounts, by design.

---

## 12. Destroy Walkthrough

Per account, in this order:

```bash
# 1. Remove the ArgoCD Application first, so ArgoCD doesn't try to
#    reconcile against a cluster that's disappearing mid-destroy
kubectl delete application live-poll-app -n argocd --wait=true

# 2. Destroy in reverse creation order
cd apps/cluster-addons/envs/dev && terraform destroy
cd ../../../../infra/envs/dev    && terraform destroy
cd ../../bootstrap/envs/dev        && terraform destroy   # only for a full teardown
```

Or trigger `destroy-dev.yml` / `destroy-prod.yml` via `workflow_dispatch`, typing `DESTROY` to confirm — it already removes the ArgoCD `Application` and destroys `infra/envs/<env>` for you; run `apps/cluster-addons`'s own destroy separately first if you want that layer gone too.

Prod's `deletion_protection = true` on RDS means a plain `terraform destroy` against `infra/envs/prod` will fail until you deliberately flip that flag — a last safety net specific to the prod account.

---

## 13. Cost Estimation

Running **both** environments 24/7 roughly doubles the single-account estimate, with dev noticeably cheaper due to smaller instance types and no Multi-AZ:

| | Dev/Test (monthly) | Prod (monthly) |
|---|---|---|
| EKS control plane | ~$73 | ~$73 |
| Worker nodes | ~$15 (1x t3.small) | ~$60 (2x t3.medium) |
| NAT Gateway | ~$33 + data | ~$33 + data |
| RDS | ~$15 (t3.micro, single-AZ) | ~$110 (t3.medium, Multi-AZ) |
| ALB | ~$20 + LCU | ~$20 + LCU |
| **Total** | **~$160-180/month** | **~$300-330/month** |

Since dev is meant to be used intermittently, destroying `infra/envs/dev` and `apps/cluster-addons/envs/dev` between work sessions (and re-applying when needed) is the single biggest cost lever for that account.

---

## 14. Security Best Practices

- `bootstrap/modules/core/iam.tf` attaches `AdministratorAccess` to each account's GitHub Actions role for simplicity — flagged in the code, and doubly worth tightening here since it's now duplicated across **two** real AWS accounts. Scope both down independently.
- Put required reviewers on the `prod` GitHub Environment (Section 4) — this is the actual approval gate for anything reaching production, for both this repo's Terraform changes and `live-poll-app`'s `promote-to-prod.yml`.
- Dev and prod share **zero** IAM trust relationships — verify this stays true if you ever add anything cross-account (e.g. a shared ECR via replication); the isolation described in Section 3 depends on it.
- RDS in prod: `deletion_protection = true`, `skip_final_snapshot = false`, `multi_az = true`. Don't relax these outside of a genuine dev/test environment.

---

## 15. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `apps/cluster-addons/envs/<env>` fails with "no matches for kind Application" | First-ever apply in that account, CRD not registered yet | Run the two-pass apply from Section 6 |
| `infra/envs/prod` `terraform destroy` fails | `deletion_protection = true` on RDS | Set it to `false` in `infra/envs/prod/main.tf`, apply once, then destroy |
| Dev and prod both show the same resources in one state | Wrong `backend.tf`/wrong AWS profile | Double check `bucket` in each env's `backend.tf` and which account your credentials/profile point at before running `terraform apply` |
| GitHub Actions job can't find `secrets.AWS_ROLE_ARN` | Workflow ran without an `environment:` matching where the secret was set | Confirm the caller workflow passes `environment_name: dev` (or `prod`) into `_terraform-apply.yml` |
| `terraform apply` hangs on state lock | A previous run died mid-apply, left an S3 lock file | Confirm no apply is running, then `terraform force-unlock <ID>` in that specific env's directory |

---

## 16. FAQ

**Q: Could I run dev and prod in the same AWS account instead of two accounts?**
A: Yes — copy the `envs/dev` pattern but point its backend at a different state key within the same account/bucket instead of a different bucket, and rely on naming (`dev-` prefixes) plus IAM policy for isolation. It works, but it's meaningfully weaker isolation than what this repo defaults to — a single over-broad IAM policy can then affect both environments, which is structurally impossible with two separate accounts.

**Q: Why does `apps/cluster-addons` still need `terraform_remote_state` from `infra`, but nothing here reads from `live-poll-app`?**
A: `terraform_remote_state` only works between two Terraform projects sharing a backend type this code knows how to query. `live-poll-app` has no Terraform state at all — it's plain YAML — so there's nothing for a `data` block to read. That's exactly why every ARN/endpoint it needs gets pasted into its overlay files by hand once, rather than looked up automatically. See that repo's README for the full reasoning.

**Q: What stops someone from accidentally running `infra/envs/dev`'s Terraform against the prod AWS account?**
A: Two independent layers: (1) `backend.tf` in each folder points at a completely different S3 bucket name, so even with the wrong credentials active, Terraform would fail to find matching state rather than silently operating on the wrong account's resources; (2) in CI, the `environment:` field on each workflow selects which GitHub Environment's `AWS_ROLE_ARN` gets used, and that role only exists in one specific AWS account.

## Companion Repo

Application code and GitOps deployment manifests live in [`live-poll-app`](https://github.com/yourusername/live-poll-app) — see that repo's README for the dev-to-prod promotion flow and the full trace of how a database secret moves from this repo's Terraform all the way to a running pod without ever passing through either repo's CI.
