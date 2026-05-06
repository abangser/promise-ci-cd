# Demo Guide — Promise CI/CD

Step-by-step instructions to fork this repo, stand up a local cluster, and run the full demo end-to-end.

**Estimated time:** ~20 minutes (assuming prerequisites installed).

Read [README.md](README.md) first if you want to understand what each step is doing and why.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| `kind` | v0.23+ | https://kind.sigs.k8s.io/docs/user/quick-start/#installation |
| `kubectl` | v1.28+ | https://kubernetes.io/docs/tasks/tools/ |
| `gh` CLI | latest | https://cli.github.com |

You also need:
- A GitHub [classic PAT](https://github.com/settings/tokens) with `repo` and `write:packages` scopes — used throughout as `$GITHUB_TOKEN`
- AWS credentials with `s3:*` on the buckets you want to manage

---

## Step 1 — Fork this repository

Use the `gh` CLI to fork — the GitHub UI only copies the default branch, but this demo needs all three branches (`main`, `platform-config`, `generated-promises`).

```bash
export GITHUB_TOKEN="<your-pat>"
gh repo fork abangser/promise-ci-cd --clone --remote \
  || gh repo clone "$(gh api user --jq '.login')/promise-ci-cd"
cd promise-ci-cd
FORK="$(gh api user --jq '.login')/promise-ci-cd"
gh repo edit "$FORK" --enable-issues
gh api --method PUT "repos/${FORK}/actions/permissions" -F enabled=true -f allowed_actions=all | cat
gh secret set GHCR_PAT --repo "$FORK" --body "$GITHUB_TOKEN"
```

The `platform-config` branch has `<ORG>` placeholders that point back to your fork. Replace them now:

```bash
ORG=$(git remote get-url origin | sed -E 's|.*github\.com[:/]([^/]+)/.*|\1|')
git fetch origin platform-config
git checkout -B platform-config origin/platform-config
perl -pi -e "s|<ORG>|${ORG}|g" gitrepository.yaml gitstatestore.yaml
git add gitrepository.yaml gitstatestore.yaml
git commit -m "chore: configure org name"
git push origin platform-config
git checkout main
```

---

## Step 2 — Stand up a local cluster

The Kratix quick-start installer sets up everything the platform needs in one command: cert-manager, Kratix, MinIO, and Flux.

```bash
kind create cluster --name platform
export PLATFORM=kind-platform

kubectl --context $PLATFORM apply \
  --filename https://github.com/syntasso/kratix/releases/latest/download/kratix-quick-start-installer.yaml

for ns in cert-manager flux-system kratix-platform-system; do
  echo "Waiting for $ns..."
  until kubectl --context $PLATFORM get deployments -n $ns 2>/dev/null | grep -q .; do sleep 5; done
  kubectl --context $PLATFORM wait deployment --all \
    --for=condition=available --timeout=300s -n $ns
done
```

---

## Step 3 — Create the cluster secrets

Three secrets are needed — one for each component that needs credentials:

```bash
# Kratix writes pipeline outputs back to GitHub
kubectl --context $PLATFORM create secret generic git-credentials \
  --namespace=kratix-platform-system \
  --from-literal=username=<YOUR_GITHUB_USERNAME> \
  --from-literal=password="$GITHUB_TOKEN"

# Pipeline pods open GitHub Issues for the approval gate
kubectl --context $PLATFORM create secret generic github-token \
  --namespace=default \
  --from-literal=token="$GITHUB_TOKEN"

# Pipeline pods provision S3 buckets
kubectl --context $PLATFORM create secret generic aws-credentials \
  --namespace=default \
  --from-literal=access-key-id=<AWS_ACCESS_KEY_ID> \
  --from-literal=secret-access-key=<AWS_SECRET_ACCESS_KEY> \
  --from-literal=region=us-east-1
```

> **Note:** For production use, prefer IAM roles or a secrets manager over static credentials.

---

## Step 4 — Bootstrap Kratix and Flux

Apply the four resources from `platform-config` that wire Kratix and Flux to your fork. This is a one-time manual step — these resources are the foundation everything else depends on.

```bash
git fetch origin platform-config
bootstrap_dir=$(mktemp -d)
git archive origin/platform-config | tar -x -C "$bootstrap_dir"
kubectl --context $PLATFORM apply -f "$bootstrap_dir/"
rm -rf "$bootstrap_dir"

kubectl --context $PLATFORM wait gitrepository promise-ci-cd \
  --for=condition=Ready --timeout=120s -n flux-system

kubectl --context $PLATFORM wait destination platform \
  --for=condition=Ready --timeout=120s
```

> **Note:** The `promise-ci-cd-generated` GitRepository (watching `generated-promises`) will not become Ready until CI pushes to that branch in the next step.

---

## Step 5 — Wait for CI to generate the Promise

The GitHub Actions workflow runs automatically on every push. It reads the Terraform module in `tf-modules/` and generates a Kratix Promise from it. Watch it run:

```bash
REPO="$(gh api user --jq '.login')/promise-ci-cd"
gh run watch --repo "$REPO" \
  $(gh run list --repo "$REPO" --limit 1 --json databaseId --jq '.[0].databaseId')
```

Once this completes with 'success', Flux picks up the newly written Promise from `generated-promises` and applies it to the cluster. Confirm it has been registered:

```bash
kubectl --context $PLATFORM get promises
```

---

## Step 6 — Submit a ResourceRequest

The generated Promise registered a new Kubernetes API. Submit a request against it:

```bash
git fetch origin generated-promises

git show origin/generated-promises:s3-bucket-promise/example-resource.yaml \
  | kubectl --context $PLATFORM apply -f -
```

Kratix runs a pipeline with two stages:

**Stage 1 — Approval gate.** A GitHub Issue is opened containing your request. Find the link in the resource status:

```bash
kubectl --context $PLATFORM get s3buckets -n default -o yaml \
  | yq '.items[].status'
```
This will show that an approval issue has been opened and that the workflow is in phase "suspended" awaiting approval.

Go to the issue and close it to decide:
- Close as **"completed"** → approved, pipeline continues
- Close as **"not planned"** → rejected, pipeline stops

**Stage 2 — Terraform inputs.** Once approved, Kratix writes a `.tfvars` file to `tf-resources/` in this repo:

```bash
git pull origin main
ls tf-resources/
```

From here, applying the Terraform is up to your platform setup — the `.tfvars` file is the handoff point. Choosing to apply this in the workflow rather than writing to git is an option, as is using Terraform enterprise, a CI/CD pipeline, and really any other existing patterns for running plan and apply commands.

## Playground — Now you are all set up!

You are welcome to use this environment to experiement with different generation commands, terraform modules and more. It is also safe to clean up with a simple `kind delete clusters` as the repository does not generate any AWS resources unless a reconciler is set up for the terraform code.

---

## Troubleshooting

### Pipeline pod fails to pull image (package is private)

GHCR packages are private by default. The CI pipeline attempts to set them public but this API call is unreliable for repository-linked packages. If a pipeline pod fails with an image pull error, set the package public manually.

Find the settings URL for each package in your fork:

```bash
OWNER=$(gh api user --jq '.login')
gh api "users/${OWNER}/packages?package_type=container" --jq '.[].name' | \
  while IFS= read -r pkg; do
    echo "https://github.com/users/${OWNER}/packages/container/${pkg}/settings"
  done
```

Open each URL, scroll to "Danger Zone", and set visibility to **Public**.
