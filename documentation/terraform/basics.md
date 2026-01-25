# Terraform Basics

This document captures the baseline Terraform concepts and workflows used in this repository. It is intended as a practical reference for running Terraform consistently and safely in a professional environment.

## What Terraform Does

Terraform is an Infrastructure as Code (IaC) tool that:
- Describes desired infrastructure in declarative configuration (`.tf` files).
- Creates an execution plan by comparing configuration to the current state.
- Applies changes to converge real infrastructure to the declared desired state.

Terraform tracks managed resources in a state file and uses state locking to prevent concurrent modifications.

## Repository Layout

Terraform code is organized using a “root modules + reusable modules” approach:

- **Root modules** (deployable units, each with its own state):
  - Located under `infrastructure/live/<environment>/<component>/`
  - Example: `infrastructure/live/development/scaleway-workers/`

- **Reusable modules** (shared building blocks):
  - Located under `infrastructure/modules/<module-name>/`
  - Called from root modules via `module` blocks

Each root module is typically mapped 1:1 to a remote state workspace (e.g., in HCP Terraform).

## Core Files and Their Roles

### `variables.tf`
Declares input variables for a module:
- Name, type, default values
- Descriptions and sensitivity
- Defines the “interface” of a root module or reusable module

Example:
- `cfke_cluster_id`
- `worker_count`
- `scaleway_region`, `scaleway_zone`

### `terraform.tfvars` (or `*.tfvars`)
Provides concrete values for the variables declared in `variables.tf`.
- Used to supply environment-specific configuration (development vs production)
- Typically not committed if it contains sensitive values or developer-specific overrides

### Environment variables
Used for runtime configuration, most commonly:
- Provider authentication credentials
- Provider defaults supported by the provider

In this repository, credentials are supplied via environment variables (and may later be sourced from Vault or CI). This avoids committing secrets to Git and reduces the risk of secrets being written into Terraform configuration or logs.

### `backend` configuration (remote state)
Terraform state should not be stored in Git. A remote backend provides:
- Secure state storage
- Locking to prevent concurrent applies
- State history (depending on backend)

This repository uses HCP Terraform as the remote backend for state and locking.

## Terraform Command Workflow

### Format
Formats `.tf` files to Terraform’s canonical style:
```bash
terraform fmt -recursive
````

### Initialize

Initializes providers and the backend:

```bash
terraform init
```

### Validate

Checks configuration for internal consistency:

```bash
terraform validate
```

### Plan

Shows the changes Terraform would make:

```bash
terraform plan
```

### Apply

Applies the planned changes:

```bash
terraform apply
```

### Destroy (use with caution)

Destroys resources managed by the current root module:

```bash
terraform destroy
```

## State and Locking

Terraform state contains a representation of managed resources and may include sensitive data depending on how variables and resources are modeled. Best practices:

* Use a remote backend with locking.
* Avoid placing secrets into Terraform inputs that get persisted into state.
* Prefer provider-supported environment variables for credentials.

## Input Precedence (How Terraform Chooses Variable Values)

When the same variable is defined in multiple places, Terraform uses a defined precedence. Common sources include:

* `terraform.tfvars` / `*.tfvars`
* `-var` / `-var-file` CLI flags
* environment variables in the form `TF_VAR_<name>`
* defaults in `variables.tf`

Provider credentials are typically not Terraform input variables; they are read directly by the provider via environment variables.

## Practical Recommendations for This Repository

* Treat each directory under `infrastructure/live/...` as a separate deployable unit with its own state.
* Do not commit secrets to Git.
* Keep `terraform.tfvars` non-sensitive or uncommitted; use environment variables (or Vault) for credentials.
* Run `terraform plan` before `terraform apply` and review diffs carefully.
* Keep state remote (HCP Terraform) and do not store it in GitHub.

## Troubleshooting Notes

* Authentication failures are most commonly due to missing provider environment variables.
* Backend/state issues typically indicate missing HCP Terraform login or workspace/backend misconfiguration.
* If a plan shows unexpected changes, confirm the correct root module directory is being used and that the intended `tfvars` values are loaded.

```
