# Promise CI/CD Demo

Different infrastructure teams use different tools. Developers want self-service. Platform engineers are stuck in the middle — translating between them.

This repo shows how to close that gap:
* **producers** (Infrastructure Operations Engineers) deliver automation in whatever language suits them — Terraform, Helm, shell scripts, or any tool that runs in a container
* a **CI/CD pipeline** wraps each producer's output as a Kratix Promise
* **consumers** (Software Developers) self-serve infrastructure through a consistent, Kubernetes-native API without knowing what's running underneath.

Producers stay in their own tools; the platform engineer defines a coherent experience for everyone.

> [!NOTE]
> This is a demo repository intended to illustrate patterns, not a production-ready solution. If you'd like to discuss how these patterns apply to your specific context, [get in touch with Syntasso](https://www.syntasso.io).

## The Three Roles

| Role | Responsibility | Output |
|------|----------------|--------|
| **Infrastructure Operations Engineer** | Deliver infrastructure automation in their language of choice (Terraform in this demo) | Terraform module in `tf-modules/` |
| **Platform Engineer** | Provide the CI/CD pipeline that wraps producer outputs as Kratix Promises and deploys them | `.github/workflows/` + Kratix cluster |
| **Software Developer** | Request infrastructure via a portal or CLI — no knowledge of the producer's tooling required | ResourceRequest applied to the cluster |

The clean boundary between these roles is the point: each team works in their own layer and hands off to the next without needing to understand the others' tools.

## How It Works

**The handoff** (this demo — Terraform):

```
variables.tf  →  CI: kratix init  →  generated-promises branch  →  Flux applies Promise  →  Kratix registers new API  →  developer submits ResourceRequest  →  Kratix runs Terraform pipeline  →  infrastructure
```

**Kratix concepts used in this flow:**

| Concept | What it is |
|---------|------------|
| **Promise** | A set of instructions written in YAML that produces a resource whenever invoked. Defines the API contract, dependencies, and workflow that runs when a developer requests the service. |
| **ResourceRequest** | A document platform users write following the Promise's API contract to request an instance of a Promised service. Submitting it can by by any interface including a portal, AI agent, chatbot, or Kubernetes directly and it activates the Promise's provisioning workflow. |
| **Destination** | The representation of a system that Kratix can write documents to; those documents are then reconciled by an external tool. These are backed by a state store backed (a Git repository in this demo) |

> **Note:** This demo is opinionated on Terraform as the Infrastructure as Code example and Flux as the GitOps agent, but the same wrapping and scheduling patterns apply to any tooling that can be substituted in.

## Repository Structure

This repository uses three branches to separate concerns between the three roles described above. That structure is intentional: Kratix is built around the idea that different teams own different layers of the platform, and the branch layout makes those boundaries visible. 

> Note: It is recommended to use different repositories in production, and this demo uses branches to keep a small footprint.

| Branch | Owned by | How it changes |
|--------|----------|----------------|
| `main` | Infrastructure Operations Engineer | Pushes Terraform modules; Kratix also writes ResourceRequest pipeline outputs here |
| `platform-config` | Platform Engineer | This is the manifests required to configure and support Kratix as an orchestrator |
| `generated-promises` | Platform Engineer (via CI) | Fully CI-managed on every push to `tf-modules/` — never edit manually and populates Kratix with Promises to orchestrate |

The Software Developer does not interact with any branch directly. They submit a ResourceRequest to the cluster (via a Portal, agentic AI or other interface of choice); Kratix processes it and writes the outputs to `tf-resources/` on `main` via the Destination.

---

### `main` — Infrastructure Operations Engineer's modules + Kratix output target

```
promise-ci-cd/                        [main branch]
├── .github/
│   ├── scripts/                      # Individual steps called by the CI pipeline
│   └── workflows/
│       └── wrap-promise.yaml         # Platform Engineer's CI/CD handover pipeline
├── tf-modules/
│   └── s3-bucket/                    # Infra Ops Engineer's Terraform module
│       ├── versions.tf
│       ├── main.tf
│       ├── variables.tf              # Curated inputs — defines the developer-facing API
│       └── outputs.tf
└── tf-resources/                     # AUTO-MANAGED by Kratix — do not edit manually
                                      # Kratix writes pipeline outputs here via the GitStateStore.
```

`main` serves two purposes that reflect how Kratix closes the loop: the Infra Ops module comes in through `tf-modules/`, and the result of a developer's ResourceRequest comes back out through `tf-resources/`. Both live here because `main` is the branch that contains all of the infrastructure operations engineer's work.

---

### `platform-config` — Platform Engineer's bootstrap configuration

```
promise-ci-cd/                        [platform-config branch]
├── destination.yaml                  # Kratix Destination — registers this cluster as a target
├── gitstatestore.yaml                # Kratix GitStateStore — provides access to Kratix for write actions
├── gitrepository.yaml                # Flux: watches main (for tf-resources/) and generated-promises
└── flux-kustomization.yaml           # Flux: two Kustomizations — one applies the Promise catalog
```

These four resources are the wiring that connects connects a user to the infrastructure as code via a user friendly API.

The Platform Engineer applies these once at cluster bootstrap time. After that, Kratix and Flux handle reconciliation automatically — the Platform Engineer's ongoing work shifts to the CI pipeline.

---

### `generated-promises` — Platform Engineer's Promise catalog (CI-managed)

```
promise-ci-cd/                        [generated-promises branch — CI-managed, never edit manually]
├── kustomization.yaml                # Kustomize index — Flux applies this directory to the cluster
└── s3-bucket-promise/
    ├── promise.yaml                  # AUTO-GENERATED by CI — defines the CRD and pipeline for S3 buckets
    └── example-resource.yaml         # AUTO-GENERATED by CI — a ready-to-submit ResourceRequest example
```

Each terraform module is translated into a Kratix Promise: it defines the API contract developers use to request a resource, plus the pipeline Kratix runs when they do. Flux watches this branch and applies new or updated Promises to the cluster automatically — when a Promise lands here, Kratix registers it as a new Kubernetes API and developers can start submitting ResourceRequests against it immediately.

The `example-resource.yaml` is generated alongside each Promise to give developers a concrete example of the Software Developer's interaction with the Platform Engineer's APIs.

## Demo Flow

### Act 1 — Infra Ops Engineer: Deliver the Module

The infra ops engineer selects [`terraform-aws-modules/s3-bucket/aws`](https://registry.terraform.io/modules/terraform-aws-modules/s3-bucket/aws) from the Terraform Registry and writes a thin wrapper that exposes only the variables a developer should control.

The critical file is `variables.tf` — it defines the developer-facing API that the Kratix CLI will read to generate the Promise's CRD:

```hcl
# tf-modules/s3-bucket/variables.tf
variable "bucket_name"        { type = string }
variable "versioning_enabled" { type = bool, default = false }
variable "environment"        { type = string, default = "dev" }
```

The infra ops engineer pushes to `main`. Their job ends here.

---

### Act 2 — GitHub Actions: The Handover Pipeline

On every push to `tf-modules/**`, the pipeline processes each module directory:

1. Derives the Kubernetes kind from the directory name (`s3-bucket` → `S3Bucket`, `rds-postgres` → `RdsPostgres`)
2. Runs `kratix init tf-module-promise` — reads `variables.tf` and generates a Kratix Promise with a matching CRD, requiring no manual Promise authoring
3. Bumps the Promise version if the generated content has changed
4. Enhances the generated `example-resource.yaml` with namespace and schema defaults
5. Registers the Promise in `platform-api/kustomization.yaml` if it is new
6. Commits all updated Promises to the `generated-promises` branch — keeping `main` free of CI bot commits

Adding a new module (e.g. `tf-modules/rds-postgres/`) requires no changes to the pipeline — it is picked up automatically on the next push.

Flux watches the `generated-promises` branch and applies any new or updated Promise YAMLs to the cluster. Kratix processes each applied Promise and registers it as a new Kubernetes API — at that point developers can start submitting ResourceRequests against it.

---

### Act 3 — Developer: Self-Service Request

A developer submits a ResourceRequest — a standard Kubernetes resource that matches the API defined in the Promise. This can be done via a portal, but in this demo you apply it directly. The generated example lives on the `generated-promises` branch alongside the Promise:

```bash
git fetch origin/generated-promises
git show origin/generated-promises:s3-bucket-promise/example-resource.yaml \
  | kubectl apply -f -
```

Kratix receives the ResourceRequest, schedules a pipeline pod on the cluster, and runs it. The pipeline reads the request spec, generates Terraform inputs (a `.tfvars` file), and writes them to the GitStateStore — `tf-resources/` in this repo. The pod does **not** call `terraform apply`; it produces the inputs and hands off.

From there, applying the Terraform depends on the platform's setup: the Promise pipeline image can run `terraform apply` directly in the pod (self-contained), or the GitStateStore commit can trigger an external workflow such as GitHub Actions, Atlantis, or Terraform Cloud (reusing an existing apply process). Either way, the developer never touches Terraform or Kubernetes beyond submitting the request.

---

### Encore — Infra Ops Engineer: Extending to More Offerings

The pipeline is module-agnostic and can be extended to include any additional business requirements.

Whether you want to add cost checking, auditing, linting, or manual approvals, the Platform Engineers can now enable other specialists from around the organisation to add to the infrastructure work without having to know Terraform.

In addition, you can swap in any Terraform module and this CI pipeline can handle the rest:

| Promise | Terraform module |
|---------|-----------------|
| PostgreSQL database | `terraform-aws-modules/rds/aws` |
| VPC + subnets | `terraform-aws-modules/vpc/aws` |
| EKS cluster | `terraform-aws-modules/eks/aws` |
| GitHub repository | `mineiros-io/repository/github` |

The infra ops engineer adds the new module under `tf-modules/<name>/` with a `variables.tf` that defines the developer-facing inputs. On the next push to `main`, the workflow detects the new directory, derives the kind name automatically, and generates and publishes the Promise. No changes to the workflow are needed.

---

### Encore 2 — Platform Engineer: Encoding Organisational Rules

Adding modules is one dimension of platform growth. The other is encoding the *rules* your organisation uses to govern infrastructure: who approves requests, what costs are acceptable, which policies must be satisfied before a resource is provisioned.

This is where many internal developer platforms stall. The automation works, but each team grafts its own approval process, its own cost gate, its own compliance check on top — and the platform becomes a collection of scripts rather than a coherent product.

Kratix Promises give the platform engineer a place to inject these business-relevant stages into the pipeline in a way that is **module-agnostic and developer-transparent**. The developer submits the same ResourceRequest. The Infra Ops engineer's `variables.tf` is untouched. The platform engineer adds the gate once, and it applies to every module in the catalog.

**The GitHub sign-off stage** is an example built on the [Kratix pipeline marketplace](https://github.com/syntasso/kratix-marketplace/tree/main/pipeline-marketplace-images/github-sign-off). When a developer submits a ResourceRequest, Kratix runs the resource pipeline — and the first container in that pipeline now opens a GitHub Issue containing the full request spec. The pipeline pod waits. A human reviews and closes the issue as "completed" (approve) or "not planned" (reject). Only then does the `terraform-generate` container run.

The sign-off container reuses the GitHub token already in the cluster for GitStateStore writes — no new infrastructure to provision for the gate itself.

```
Developer submits ResourceRequest
  → Kratix schedules pipeline pod
    → github-sign-off: opens Issue, blocks until closed
    → terraform-generate: writes .tfvars to GitStateStore   (only if approved)
  → Flux picks up tf-resources/
  → Terraform applies
```

**Why this matters for how the platform works.** The three-role boundary from the start of this README is not just organisational tidiness — it is the mechanism by which the platform can grow without becoming a coordination bottleneck. Each role changes its own layer:

- The Infra Ops engineer adds a new module under `tf-modules/` — the platform picks it up.
- The Platform engineer adds a governance stage to the CI pipeline — it applies to all modules, existing and future.
- The developer submits a ResourceRequest — the same interface works regardless of what's underneath or what gates have been added.

This is what Syntasso means by *platform as a product*. A platform is not just automation — it is a set of contracts, guardrails, and self-service surfaces that encode your organisation's knowledge about how infrastructure should be used. The sign-off gate is one example. Cost estimation, policy checks, security scanning, and environment-based promotion rules are others. They all live in the same place: the CI pipeline that wraps each module as a Promise.

**How CI regeneration is handled.** The Kratix CLI (`kratix init tf-module-promise`) regenerates each Promise from scratch on every push. The sign-off container is injected by a post-generation step in CI (`inject-sign-off.sh`) so it survives regeneration. Versioning is handled by a separate `bump-version.sh` step that runs *after* injection, so the diff compares the complete final Promise on both sides — the first time the sign-off gate is introduced it appears in the diff and increments the version, and on subsequent re-runs both sides match and no spurious bump occurs.

---

## Try It Yourself

See [RUNBOOK.md](RUNBOOK.md) for step-by-step instructions to fork this repo, stand up a local cluster, and run the full demo end-to-end (~20 minutes).
