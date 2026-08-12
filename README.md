# eks-infra-terraform

**Start here.** This is the first of three repos you'll set up. This README is written so that someone who has never used AWS, Terraform, Kubernetes, or ArgoCD before can read it top to bottom, understand *why* each piece exists, and actually get a working system running by the end.

If you already know all the concepts and just want the commands, you can skim the grey "concept" boxes and jump straight to **Part 5**. If you're new to this, read every part in order — nothing later assumes you skipped ahead.

---

## Table of Contents

- [Part 0 — What Are We Actually Building?](#part-0--what-are-we-actually-building)
- [Part 1 — Concepts You Need, Explained Simply](#part-1--concepts-you-need-explained-simply)
- [Part 2 — The Three Repos and How They Talk to Each Other](#part-2--the-three-repos-and-how-they-talk-to-each-other)
- [Part 3 — Install the Tools](#part-3--install-the-tools)
- [Part 4 — Set Up Two AWS Accounts](#part-4--set-up-two-aws-accounts)
- [Part 5 — Set Up GitHub (Repos, Environments, Secrets)](#part-5--set-up-github-repos-environments-secrets)
- [Part 6 — Deploy the Dev Environment, Step by Step](#part-6--deploy-the-dev-environment-step-by-step)
- [Part 7 — Wire Up ArgoCD and Deploy the App (Dev)](#part-7--wire-up-argocd-and-deploy-the-app-dev)
- [Part 8 — Verify Everything Is Actually Working](#part-8--verify-everything-is-actually-working)
- [Part 9 — Make a Code Change and Watch It Deploy](#part-9--make-a-code-change-and-watch-it-deploy)
- [Part 10 — Promote to Production](#part-10--promote-to-production)
- [Part 11 — Repeat Everything for Prod](#part-11--repeat-everything-for-prod)
- [Part 12 — Repository Structure Reference](#part-12--repository-structure-reference)
- [Part 13 — Module by Module Reference](#part-13--module-by-module-reference)
- [Part 14 — Cost Estimate](#part-14--cost-estimate)
- [Part 15 — Cleaning Up / Destroying Everything](#part-15--cleaning-up--destroying-everything)
- [Part 16 — Troubleshooting](#part-16--troubleshooting)
- [Part 17 — Glossary](#part-17--glossary)

---

## Part 0 — What Are We Actually Building?

In plain words: a small website (a live voting app — click a button, see the vote count update instantly for everyone) running on AWS, set up the way a real company would set it up — with a proper testing environment separate from production, automated deployments, and no passwords lying around in plaintext anywhere.

By the end of this guide you will have:

1. **Two separate AWS accounts** — one for testing (`dev`), one for real users (`prod`) — each running a small Kubernetes cluster, a database, and the app.
2. **A CI/CD pipeline** — so that when you change the app's code and push it to GitHub, it automatically builds, tests, and deploys itself to the dev environment, with no manual steps.
3. **A safe way to promote to production** — a deliberate, one-click "ship this exact thing that worked in dev" action, not a repeat of the build.
4. **Zero secrets in git** — the database password is never visible in any file you commit, ever, anywhere.

This is a **learning project**, but every piece of it — Terraform, EKS, IAM roles, GitOps, ArgoCD — is exactly what real companies use. Nothing here is a toy simplification; it's the real tools, sized down.

---

## Part 1 — Concepts You Need, Explained Simply

Read this part even if some of it feels obvious — later steps refer back to these explanations, and it's much easier to follow a command like `terraform apply` if you already know what "state" means.

> **What is AWS?**
> Amazon Web Services. Instead of buying physical computers, you rent virtual computers, storage, databases, and networking from Amazon, and pay only for what you use. Everything in this project runs *inside* AWS.

> **What is an AWS Account?**
> A completely separate, walled-off "workspace" in AWS — its own billing, its own resources, its own permissions. Two AWS accounts can't see or touch each other's resources by default, which is exactly why we use two of them: one mistake in the dev account has no way to reach the prod account.

> **What is IAM?**
> Identity and Access Management — AWS's system for controlling *who* (a person, or a piece of software) can do *what* (create a server, read a file, delete a database). Every single action in this project — Terraform creating a VPC, GitHub Actions pushing a Docker image, a pod reading a secret — goes through an IAM permission check.

> **What is Infrastructure as Code (IaC), and what is Terraform?**
> Instead of clicking buttons in the AWS web console to create a server, you write a text file describing what you want ("I want one database, this big, in this network"), and a tool reads that file and creates exactly that. Terraform is the tool we use. The benefit: your infrastructure is now a file you can read, review in a pull request, version, and re-run to get the exact same result every time.

> **What is Terraform "state"?**
> A file where Terraform keeps track of what it has already created, so that next time you run it, it knows the difference between "create this new thing" and "this already exists, leave it alone." We store this file in AWS S3 (cloud storage) rather than on your laptop, so a teammate — or a GitHub Actions robot — can also see what's already been created.

> **What is Docker, and what is a container?**
> A container is a lightweight, self-contained package of your application plus everything it needs to run (the exact Node.js version, libraries, etc.) — so it behaves identically on your laptop, in a test environment, and in production. Docker is the tool that builds and runs these packages. A `Dockerfile` is the recipe for building one.

> **What is Kubernetes?**
> A system that runs many containers across many computers, automatically restarting them if they crash, spreading them out for reliability, and routing network traffic to them. Instead of you manually deciding "run this container on this specific server," you tell Kubernetes "keep 2 copies of this container running somewhere," and it figures out the rest.

> **What is EKS?**
> Elastic Kubernetes Service — AWS's managed version of Kubernetes. AWS runs and maintains the tricky "control plane" part for you; you just bring the worker computers (nodes) that your containers actually run on.

> **What is a VPC?**
> Virtual Private Cloud — your own private, isolated network inside AWS, with your own IP address ranges, subnets, and firewall rules. Everything we create (the Kubernetes cluster, the database) lives inside one VPC per AWS account.

> **What is RDS?**
> Relational Database Service — a managed database. Instead of installing and patching MySQL yourself on a server, AWS runs it for you; you just get a connection address and use it.

> **What is a "secret," and why can't it just live in a config file?**
> A secret is any sensitive value — a database password, an API key — that would cause harm if someone unauthorized saw it. If you put it directly in a file and commit that file to git, it's now in your project's permanent history forever, readable by anyone with access to the repo (and if the repo is ever made public, by anyone on the internet). This entire project is built around the rule: **the real secret value should exist in as few places as possible, and never inside a git repository.**

> **What is AWS Secrets Manager?**
> A secure vault, inside AWS, for storing secrets like passwords. Applications ask Secrets Manager for the value at the moment they need it, using an AWS permission check — the value itself never has to be written into any file.

> **What is IRSA (IAM Roles for Service Accounts)?**
> The mechanism that lets a specific piece of software running inside Kubernetes (not a person, not a whole server — one specific application) get its own temporary, narrowly-scoped AWS permissions, with **no password or key file involved at all.** It works through a trust relationship between Kubernetes and AWS IAM. This is how our app reads the database password from Secrets Manager without that password ever being written into a Kubernetes YAML file.

> **What is GitOps?**
> An approach where the *desired state* of your running application is described entirely in files stored in a git repository, and a piece of software running in your cluster continuously makes reality match those files. To deploy a new version, you don't run a manual command against the cluster — you just change a file in git (usually "which image version to run") and commit it. This gives you a complete, reviewable history of every deployment, and automatic recovery if someone changes something by hand.

> **What is ArgoCD?**
> The specific GitOps tool we use. It runs inside the Kubernetes cluster, watches a folder in a git repository, and applies whatever it finds there to the cluster — continuously, automatically, forever.

> **What is Kustomize?**
> A tool for managing slightly-different versions of the same Kubernetes configuration (e.g., "the dev version" vs "the prod version") without copy-pasting every file. You write one shared `base/` version, and small `overlays/` that patch just the handful of fields that differ.

> **What is CI/CD?**
> Continuous Integration / Continuous Deployment. Automated pipelines that run every time you push code — building it, testing it, and (for CD) deploying it — without a human manually running those steps. We use **GitHub Actions** for this.

> **What is OIDC, and why does it matter here?**
> A way for GitHub Actions to prove its identity to AWS and get temporary permissions, without ever storing a long-lived AWS password/key as a GitHub secret. This matters because a leaked long-lived AWS key is a permanent problem until manually revoked; a leaked OIDC-issued temporary credential expires on its own within the hour.


---

## Part 2 — The Three Repos and How They Talk to Each Other

This project is split across **three separate GitHub repos**, on purpose (the reasoning is explained in full in each repo's own README — this section is just the map).

```
1. eks-infra-terraform   (THIS repo — you're reading it now)
   → Terraform only. Creates the AWS infrastructure: network, Kubernetes
     cluster, database, permissions, and installs ArgoCD itself.
   → You run this with the `terraform` command, or GitHub Actions runs
     it for you.

2. live-poll-app
   → The actual application source code (a small Node.js app).
   → When you push code here, a pipeline builds a Docker image and
     pushes it to AWS, then tells repo #3 "deploy this new version."

3. live-poll-app-deploy
   → Plain Kubernetes configuration files — no app code, no Terraform.
   → ArgoCD (installed by repo #1) watches this repo and makes the
     cluster match whatever's in here.
```

**Why three repos and not one?** Think of it like three different jobs with three different people who'd do them in a real company:

- A **platform engineer** works in repo #1. They care about network security, cluster sizing, database backups. They should never need to touch application code.
- An **app developer** works in repo #2. They care about the app's features and bugs. They should never need AWS credentials or Kubernetes knowledge.
- **Nobody manually works in repo #3.** It's written to only by automated pipelines — it's the "current truth" of what's deployed, and its git history is a complete deployment log.

You'll set up all three repos as part of this guide, but you're reading repo #1's README because **this is where you start** — nothing in repo #2 or #3 works until the AWS infrastructure in repo #1 exists.

---

## Part 3 — Install the Tools

Install these on your own computer (Mac, Linux, or Windows with WSL2) before continuing:

| Tool | What it's for | Install |
|---|---|---|
| **AWS CLI v2** | Talk to AWS from your terminal | [docs.aws.amazon.com/cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| **Terraform** (>= 1.10) | Create AWS infrastructure from code | [developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads) |
| **kubectl** | Talk to a Kubernetes cluster | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| **Docker** | Build container images | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| **Git** | Version control, push code | Usually pre-installed; if not, [git-scm.com](https://git-scm.com/downloads) |
| **kustomize** | Manage dev/prod config differences (repo #3) | [kubectl.docs.kubernetes.io/installation/kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) |

After installing, confirm each one works:

```bash
aws --version
terraform -version      # must say 1.10.0 or higher
kubectl version --client
docker --version
git --version
kustomize version
```

If any of these commands say "command not found," go back and reinstall that tool before continuing — nothing later in this guide will work without all six.

---

## Part 4 — Set Up Two AWS Accounts

You need **two AWS accounts** — genuinely two separate accounts, not two regions or two sets of resources in one account. If you've never made more than one AWS account before:

1. Go to [aws.amazon.com](https://aws.amazon.com) and create your first account — this will be your **dev/test account**. You'll need an email address and a credit/debit card (AWS has a free tier, but some resources in this project, like the database and load balancer, do cost a small amount — see [Part 14](#part-14--cost-estimate)).
2. For the **second (prod) account**, the easiest path if you're doing this alone is [AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_create.html) — from your first account, go to the AWS Organizations console and click "Add an AWS account." This creates a second, fully separate account without needing a second credit card or email (it can reuse your first account's billing).
3. Note down each account's **12-digit Account ID** (visible in the top-right of the AWS Console, under your username) — you'll need to tell them apart throughout this guide. From here on, this guide calls them **the dev account** and **the prod account**.

### Create an IAM user for the very first setup step

In **each** account, you need one IAM user with enough permissions to run the one-time `bootstrap` step (everything after that uses OIDC, no long-lived credentials at all — see the concept box on OIDC above).

1. In the AWS Console, switch to the dev account. Go to **IAM → Users → Create user**.
2. Name it something like `terraform-bootstrap`.
3. Attach the **AdministratorAccess** policy directly (this is a one-time setup user — you'll delete its credentials once bootstrap has run successfully).
4. Go to that user → **Security credentials → Create access key** → choose "Command Line Interface (CLI)" → save the **Access Key ID** and **Secret Access Key** somewhere safe (a password manager, not a text file in this repo!).
5. Repeat steps 1-4 in the **prod account**.

You now have two access-key pairs — one per account. Configure them as named profiles on your machine so you can easily switch between accounts:

```bash
aws configure --profile dev-account
# paste the dev account's Access Key ID / Secret Access Key when prompted
# region: ap-south-1 (or whichever region you prefer)

aws configure --profile prod-account
# paste the prod account's Access Key ID / Secret Access Key
```

Test each one:

```bash
aws sts get-caller-identity --profile dev-account
aws sts get-caller-identity --profile prod-account
```

Each command should print an `Account` field with a different 12-digit number — if both print the *same* account number, you set up the profiles against the same account by mistake; go back and check.

---

## Part 5 — Set Up GitHub (Repos, Environments, Secrets)

### Create the three repos

On GitHub, create three **empty** repositories (no README, no `.gitignore` — you'll push these from the zip files you already have):

1. `eks-infra-terraform`
2. `live-poll-app`
3. `live-poll-app-deploy`

Push each folder into its matching repo:

```bash
# from inside the eks-infra-terraform folder
git init
git add .
git commit -m "initial commit"
git branch -M main
git remote add origin https://github.com/<your-username>/eks-infra-terraform.git
git push -u origin main
```

Repeat the same four commands (`git init` through `git push`) inside the `live-poll-app` folder and the `live-poll-app-deploy` folder, pointing each `git remote add` at its own repo URL.

### Create GitHub Environments

**In the `eks-infra-terraform` repo**, go to **Settings → Environments** and create two environments: `dev` and `prod`. Do the exact same thing in `live-poll-app` (you'll only need a `dev` environment there) and in `live-poll-app-deploy` (no environments needed there yet — its secrets are repository-level, explained in that repo's README).

For the `prod` environment in `eks-infra-terraform` (and later, in `live-poll-app-deploy`), click **Required reviewers** and add yourself (or a teammate) — this means any workflow that touches prod will pause and wait for a manual click to approve, which is your safety net against an accidental production change.

### Add secrets to `eks-infra-terraform`

Under the `dev` environment, add these secrets (**Settings → Environments → dev → Add secret**):

| Secret name | Value |
|---|---|
| `AWS_REGION` | e.g. `ap-south-1` |
| `AWS_BOOTSTRAP_ACCESS_KEY_ID` | the dev account IAM user's Access Key ID from Part 4 |
| `AWS_BOOTSTRAP_SECRET_ACCESS_KEY` | the dev account IAM user's Secret Access Key from Part 4 |

Under the `prod` environment, add the same three secrets, but using the **prod account's** IAM user credentials instead.

You'll add one more secret to each environment (`AWS_ROLE_ARN`) after Part 6 — it doesn't exist yet because `terraform apply` hasn't created it.

---

## Part 6 — Deploy the Dev Environment, Step by Step

Everything from here runs on your own computer first (so you can see exactly what's happening), using the `dev-account` AWS profile you set up in Part 4. Later, GitHub Actions will do these same steps automatically.

### Step 6.1 — Bootstrap (creates the "foundation": a place for Terraform to store its state, and a secure identity for GitHub Actions)

```bash
cd bootstrap/envs/dev
```

Open `terraform.tfvars` in this folder and check the values — especially `state_bucket_name` (must be a **globally unique** name across all of AWS, not just your account — add your name or a random number if `eks-dev-001-tf-state` is already taken) and `github_repository` (set this to `<your-username>/eks-infra-terraform`).

```bash
terraform init
```
> **What just happened?** Terraform downloaded the AWS plugin it needs and set up a local working directory. You'll see a new hidden `.terraform` folder — safe to ignore, never commit it (it's already in `.gitignore`).

```bash
terraform plan -var="aws_profile=dev-account"
```
> **What just happened?** Terraform compared "what you've asked for in the `.tf` files" against "what actually exists in AWS" (nothing yet) and printed a list of what it *would* create, without creating anything. Read through it — you should see an S3 bucket, an IAM OIDC provider, and an IAM role being planned.

```bash
terraform apply -var="aws_profile=dev-account"
```
> Type `yes` when prompted. This is the step that actually creates things in AWS. Wait for it to finish — it should take under a minute.

When it's done, run:

```bash
terraform output
```

You'll see two values: `terraform_state_bucket` and `github_actions_role_arn`. **Copy the `github_actions_role_arn` value** — go back to GitHub, **Settings → Environments → dev**, and add it as a new secret named `AWS_ROLE_ARN`.

### Step 6.2 — Point the backend files at your real bucket name

If you changed `state_bucket_name` in Step 6.1 (because the default was already taken), update it in these two files to match:
- `infra/envs/dev/backend.tf`
- `apps/cluster-addons/envs/dev/backend.tf`

(Both already say `eks-dev-001-tf-state` — only change this if your bucket name is different.)

Commit and push this change:
```bash
cd ../../..
git add infra/envs/dev/backend.tf apps/cluster-addons/envs/dev/backend.tf
git commit -m "chore: set real dev state bucket name"
git push
```

### Step 6.3 — Create the actual infrastructure (network, Kubernetes cluster, database)

```bash
cd infra/envs/dev
terraform init
terraform plan -var="aws_profile=dev-account"
```

> Read through this plan carefully — this is the big one. You should see roughly 40-60 resources being created: a VPC, subnets, an EKS cluster, a node group, IAM roles, an RDS database, ECR repositories, an S3 bucket, and a Secrets Manager secret.

```bash
terraform apply -var="aws_profile=dev-account"
```

Type `yes`. **This step takes 15-20 minutes** — most of that time is AWS provisioning the EKS control plane, which you can't speed up. Get a coffee.

When it finishes:

```bash
terraform output
```

**Copy down every value shown** — you'll need most of them in the next few steps. In particular:
- `cluster_name`
- `vpc_id`
- `app_role_arn`
- `alb_controller_role_arn`
- `external_secrets_role_arn`
- `rds_endpoint`
- `ecr_app_repository_url`
- `ecr_backup_repository_url`

Now point `kubectl` at your new cluster:

```bash
aws eks update-kubeconfig --name dev-eks-cluster --region ap-south-1 --profile dev-account
kubectl get nodes
```

You should see 1 node listed with status `Ready`. If you see this, your Kubernetes cluster is real and working.

---

## Part 7 — Wire Up ArgoCD and Deploy the App (Dev)

### Step 7.1 — Install the cluster add-ons (Load Balancer Controller, External Secrets, ArgoCD)

```bash
cd ../../apps/cluster-addons/envs/dev
```

Open `terraform.tfvars` and fill in:
- `vpc_id` — from Step 6.3's output
- `git_repo_url` — set to `https://github.com/<your-username>/live-poll-app-deploy.git`

```bash
terraform init
```

> **Important — this next part needs TWO applies, and this is expected, not an error.** ArgoCD's installation brings in a new *type* of Kubernetes object (called a Custom Resource Definition, or CRD) that Terraform needs to already exist before it can create an ArgoCD "Application" object in the same run. The very first time only, run:

```bash
terraform apply -var="aws_profile=dev-account" -target=module.cluster_addons.helm_release.argocd
```

Type `yes`. Then run a completely normal apply right after:

```bash
terraform apply -var="aws_profile=dev-account"
```

Type `yes` again. (Every apply after this first-time setup only ever needs the single, normal command — this two-step dance is a one-time thing per environment.)

### Step 7.2 — Fill in the placeholders in `live-poll-app-deploy`

Clone (or `cd` into, if you already pushed it) the `live-poll-app-deploy` repo. You need to replace several `REPLACE_IN_OVERLAY`-style placeholders with the real values from Step 6.3's Terraform output.

Open **`overlays/dev/serviceaccount-patch.yaml`** and set the role ARN:
```yaml
eks.amazonaws.com/role-arn: "<paste app_role_arn here>"
```

Open **`overlays/dev/secretstore-patch.yaml`** and confirm the region matches yours (`ap-south-1` by default).

Open **`overlays/dev/deployment-patch.yaml`** and set the database host:
```yaml
value: "<paste rds_endpoint here>"
```

Open **`overlays/dev/kustomization.yaml`** and set the ECR image (without a tag yet — the build pipeline will add one automatically in Part 9, but it needs the right repository name to start):
```yaml
images:
  - name: REPLACE_IN_OVERLAY
    newName: "<paste ecr_app_repository_url here, without any :tag>"
    newTag: latest
```

(Optional for now) Open **`overlays/dev/ingress-patch.yaml`** if you have a domain and an ACM certificate ready — otherwise leave it as-is and you'll reach the app over the load balancer's raw hostname instead, which is fine for testing.

Commit and push:
```bash
git add overlays/dev/
git commit -m "chore: fill in dev environment values"
git push
```

ArgoCD (installed in Step 7.1) is already watching this exact path — within a minute or two of this push, it will notice the change and start creating things in your cluster. But there's no image to actually run yet — that's the next part.

---

## Part 8 — Verify Everything Is Actually Working

Run each of these and confirm what you see against the "expect" line:

```bash
kubectl get nodes
# expect: 1 node, STATUS = Ready

kubectl get pods -n argocd
# expect: several pods, all STATUS = Running

kubectl get application -n argocd
# expect: one row, "live-poll-app", SYNC STATUS may say OutOfSync or
# Missing right now — that's expected until Part 9, since there's no
# Docker image pushed yet

kubectl get namespace app
# expect: this namespace exists — ArgoCD already created it
```

If all four of these look right, your platform is fully working — the only missing piece is an actual application image to run, which is exactly what Part 9 does.

---

## Part 9 — Make a Code Change and Watch It Deploy

This is the payoff step — you'll see the entire pipeline work end to end.

### Step 9.1 — One-time GitHub setup for `live-poll-app`

Follow **`live-poll-app`'s own README** for a few one-time steps you need there: adding its `dev` environment's `AWS_ROLE_ARN` secret (same value as this repo's dev environment), and creating a scoped Personal Access Token so it can commit to `live-poll-app-deploy`. Come back here once that's done.

### Step 9.2 — Trigger the first build

In the `live-poll-app` repo, make any small change under `app/` — even just adding a comment to `server.js` — and push it to `main`:

```bash
cd live-poll-app
echo "// first deploy" >> app/server.js
git add app/server.js
git commit -m "trigger first dev deploy"
git push
```

### Step 9.3 — Watch it happen

Go to the **Actions** tab of `live-poll-app` on GitHub. You should see `Build and Push (dev)` running. It will:
1. Build a Docker image from `app/`
2. Push it to your dev account's ECR
3. Update `live-poll-app-deploy`'s `overlays/dev/kustomization.yaml` with the new image tag
4. Commit and push that change

Once that workflow finishes (usually 2-4 minutes), go check ArgoCD:

```bash
kubectl get application -n argocd
# SYNC STATUS should now say "Synced", HEALTH STATUS should say "Healthy"
# (give it a minute or two after the build finishes — ArgoCD polls periodically)

kubectl get pods -n app
# expect: live-poll-app pods, STATUS = Running
```

### Step 9.4 — See the actual app

```bash
kubectl get ingress -n app
```

Copy the `ADDRESS` column's value (a long `....elb.amazonaws.com` hostname) and open `http://<that address>` in your browser. You should see the live poll page — click a button and watch the count update.

**If you got here and it works — congratulations, you've deployed a complete, production-pattern application to AWS, entirely through code.**

---

## Part 10 — Promote to Production

Once you're happy with what's running in dev, promoting the exact same, already-tested image to prod is a deliberate, separate action — it never rebuilds anything.

1. Find the git SHA that was deployed to dev — either from the `live-poll-app` Actions tab (the commit that triggered the successful build), or by looking at `live-poll-app-deploy`'s `overlays/dev/kustomization.yaml` on GitHub (the `newTag` value).
2. Go to the `live-poll-app-deploy` repo's **Actions** tab → `Promote to Prod` → **Run workflow** → paste that SHA into the `image_tag` field → **Run workflow**.
3. If you set up a required reviewer on the `prod` GitHub Environment, you'll see the job pause with an "Awaiting approval" state — click into it and approve it.
4. Once it completes, it has: pulled that exact image from dev's ECR, pushed the same bytes into prod's ECR, and updated `overlays/prod/kustomization.yaml`.

This won't actually deploy anywhere yet, though, until you've set up the **prod AWS account and prod EKS cluster** — which is Part 11.

---

## Part 11 — Repeat Everything for Prod

Once dev is fully working, set up prod by repeating **Part 6 and Part 7**, with these swaps everywhere:

- Use the `prod-account` AWS profile instead of `dev-account`
- Work in `bootstrap/envs/prod`, `infra/envs/prod`, `apps/cluster-addons/envs/prod` instead of the `dev` folders
- Fill in `live-poll-app-deploy`'s `overlays/prod/` files instead of `overlays/dev/`
- Add secrets to the `prod` GitHub Environment (in this repo) using the **prod account's** values
- `live-poll-app-deploy` also needs two **repository-level** secrets (not environment-scoped) for the cross-account promotion workflow: `AWS_DEV_ROLE_ARN` and `AWS_PROD_ROLE_ARN` — see that repo's README for exactly where these go

Once prod's cluster add-ons are applied and `overlays/prod/` is filled in, re-run the `Promote to Prod` workflow from Part 10 (or run it for the first time now) — prod's ArgoCD instance will pick up the change the same way dev's did.

---

## Part 12 — Repository Structure Reference

```
eks-infra-terraform/
├── bootstrap/
│   ├── modules/core/                # shared logic: S3 state bucket + GitHub OIDC provider + role
│   └── envs/dev/  envs/prod/        # one root module per AWS account — run once each, ever
│
├── infra/
│   ├── modules/                     # shared: network, iam, eks, irsa, rds, secrets-manager, ecr, backup
│   └── envs/dev/  envs/prod/        # one root module per AWS account — different sizing per env
│
├── apps/cluster-addons/
│   ├── modules/                     # shared: alb-controller.tf, external-secrets.tf, argocd.tf
│   └── envs/dev/  envs/prod/        # each points its ArgoCD at a different overlay path
│
├── backup-job/                       # Docker image + kubectl-applied manifests for DB backups
│
└── .github/workflows/
    ├── _terraform-apply.yml          # shared logic used by every other workflow below
    ├── bootstrap-dev.yml   bootstrap-prod.yml
    ├── infra-dev.yml        infra-prod.yml
    ├── cluster-addons-dev.yml   cluster-addons-prod.yml
    └── destroy-dev.yml      destroy-prod.yml
```

Every `envs/<env>` folder is a fully independent Terraform root module — its own state file, its own AWS account, its own `terraform apply`. The only thing dev and prod ever share is the `modules/` code.

---

## Part 13 — Module by Module Reference

- **`network`** — creates the VPC, 2 public subnets, 2 private subnets, 1 NAT Gateway. The EKS cluster's worker nodes and the RDS database both live in the private subnets (no direct internet access); the NAT Gateway lets them reach the internet for things like pulling container images.
- **`iam`** — two IAM roles: one the EKS control plane itself uses, one the worker node computers use.
- **`eks`** — the Kubernetes cluster itself, its worker node group, and the special identity provider (OIDC) that IRSA depends on.
- **`irsa`** — five specific, narrowly-scoped IAM roles for five specific pieces of software: the EBS storage driver, the app itself, the External Secrets Operator, the Load Balancer Controller, and the backup job. Each one can only be used by the one specific Kubernetes ServiceAccount it's meant for.
- **`rds`** — the MySQL database. Takes different sizing inputs for dev (small, cheap, disposable) vs. prod (bigger, Multi-AZ for reliability, protected from accidental deletion).
- **`secrets-manager`** — stores the database's auto-generated password securely.
- **`ecr`** — a private Docker image registry. Used twice: once for the app's image, once for the backup job's image.
- **`backup`** — an S3 bucket where database backups get uploaded.

---

## Part 14 — Cost Estimate

Running both environments 24/7:

| | Dev/Test (monthly) | Prod (monthly) |
|---|---|---|
| EKS control plane | ~$73 | ~$73 |
| Worker nodes | ~$15 | ~$60 |
| NAT Gateway | ~$33 + data | ~$33 + data |
| Database (RDS) | ~$15 | ~$110 |
| Load Balancer | ~$20 | ~$20 |
| **Total** | **~$160-180/month** | **~$300-330/month** |

If you're just learning, the biggest thing you can do to keep costs low is **destroy the dev environment (Part 15) whenever you're not actively using it**, and only bring up prod once you actually need it running continuously.

---

## Part 15 — Cleaning Up / Destroying Everything

Destroy in this order (reverse of how you created things), per environment:

```bash
# 1. Tell ArgoCD to stop managing the app first
kubectl delete application live-poll-app -n argocd --wait=true

# 2. Destroy the cluster add-ons
cd apps/cluster-addons/envs/dev
terraform destroy -var="aws_profile=dev-account"

# 3. Destroy the core infrastructure (cluster, database, network)
cd ../../../infra/envs/dev
terraform destroy -var="aws_profile=dev-account"

# 4. Only if you want to remove EVERYTHING including the state bucket:
cd ../../bootstrap/envs/dev
terraform destroy -var="aws_profile=dev-account"
```

Or trigger `destroy-dev.yml` (or `destroy-prod.yml`) from the Actions tab, type `DESTROY` to confirm — it handles steps 1-2-3 automatically for you.

**A safety note about prod**: prod's database has `deletion_protection = true` set. If you genuinely want to destroy it, you'll need to change that to `false` in `infra/envs/prod/main.tf`, apply that one change, and only then run `terraform destroy` — this is intentional friction so prod can't be destroyed by a single accidental command.

---

## Part 16 — Troubleshooting

| What you see | What's probably wrong | What to do |
|---|---|---|
| `terraform init` fails, mentions a bucket that doesn't exist | You haven't run `bootstrap` yet, or the bucket name in `backend.tf` doesn't match what bootstrap actually created | Go back to Step 6.1/6.2 |
| `terraform apply` in `apps/cluster-addons` fails with "no matches for kind Application" | This is the very first apply in this account, and the two-pass step (Step 7.1) was skipped | Run the `-target=module.cluster_addons.helm_release.argocd` apply first, then a normal apply |
| `kubectl get nodes` shows nothing, or times out | Your kubeconfig isn't pointed at the right cluster, or you're using the wrong AWS profile | Re-run the `aws eks update-kubeconfig` command from Step 6.3, double-check `--profile` |
| ArgoCD shows the app as `OutOfSync` and it never changes | A placeholder value (like `REPLACE_IN_OVERLAY` or `REPLACE_WITH_DEV_RDS_ENDPOINT`) is still sitting in one of the overlay files | Go back to Step 7.2 and check every file for leftover placeholders |
| ArgoCD shows `Missing` for the app's Deployment | No image has been pushed to ECR yet | Complete Part 9 |
| Pod is stuck in `CrashLoopBackOff` | Usually a database connection problem | `kubectl logs -n app deploy/live-poll-app` and check the `DB_HOST` value matches your real RDS endpoint |
| `git push` from a GitHub Actions workflow fails with a permission error | The scoped Personal Access Token for cross-repo commits (in `live-poll-app`) is missing, expired, or has the wrong permission | See `live-poll-app`'s README, "Cross-Repo Write Access" section |
| Both AWS profiles show the same Account ID | You configured both `aws configure` profiles against the same account | Go back to Part 4 and re-run `aws configure --profile prod-account` with the *prod* account's own credentials |

---

## Part 17 — Glossary

| Term | Plain-English meaning |
|---|---|
| **State** (Terraform) | A file that tracks what Terraform has already created, so it doesn't try to create the same thing twice |
| **Backend** (Terraform) | Where the state file is actually stored — here, an S3 bucket |
| **Module** (Terraform) | A reusable folder of `.tf` files, like a function you can call with different inputs |
| **Apply / Plan** | `plan` shows you what *would* change; `apply` actually makes the change |
| **Pod** (Kubernetes) | The smallest deployable unit — one or more containers running together |
| **Deployment** (Kubernetes) | A description of "keep N copies of this pod running" |
| **Service** (Kubernetes) | A stable network address that routes to a group of pods |
| **Ingress** (Kubernetes) | A rule for routing external internet traffic into the cluster, to a specific Service |
| **Namespace** (Kubernetes) | A way to group related resources together inside one cluster |
| **ServiceAccount** (Kubernetes) | An identity that a pod uses — this is what IRSA attaches AWS permissions to |
| **CRD (Custom Resource Definition)** | A way to teach Kubernetes about a brand-new *type* of object (like ArgoCD's "Application" type) |
| **OIDC** | A standard way to prove identity and get temporary access, without a stored password |
| **CI/CD** | Continuous Integration / Continuous Deployment — automated build-test-deploy pipelines |
| **Reconcile** (ArgoCD) | The act of comparing "what's in git" to "what's actually running" and fixing any difference |
| **Overlay** (Kustomize) | A small set of changes applied on top of a shared base configuration |

## Companion Repos

- [`live-poll-app`](https://github.com/yourusername/live-poll-app) — application source code and its dev build/push pipeline; no Terraform, no deployment manifests
- [`live-poll-app-deploy`](https://github.com/yourusername/live-poll-app-deploy) — GitOps manifests (Kustomize base + dev/prod overlays) that ArgoCD actually watches, plus the prod promotion workflow — see that repo's README for the full trace of how a database secret moves from this repo's Terraform all the way to a running pod without ever passing through any of the three repos' CI
