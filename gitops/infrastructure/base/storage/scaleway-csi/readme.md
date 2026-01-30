# Scaleway CSI Driver (Flux + Vault)

This folder installs the **Scaleway CSI driver** via **Flux HelmRelease** and configures it to use credentials sourced from **Vault** (synced into Kubernetes via **Vault Secrets Operator (VSO)**). It enables persistent volumes on **Scaleway nodes** in the Cloudfleet-managed hybrid cluster.

## Why this exists

In a multi-provider cluster (Hetzner + Scaleway), a StorageClass backed by Hetzner volumes (`hcloud-volumes`) cannot provision/attach volumes to Scaleway nodes. Installing Scaleway CSI provides StorageClasses backed by Scaleway Block Storage so workloads pinned to Scaleway can use PVCs.

## What is deployed

* **HelmRepository** for Scaleway charts
* **HelmRelease** for the `scaleway-csi` chart
* **ConfigMap** generated from a plain Helm values file (`scaleway-csi-values.yaml`) and consumed via `valuesFrom`
* **VSO/Vault objects** that produce a Kubernetes Secret with Scaleway credentials
* **StorageClasses** for Scaleway volumes (e.g. `scw-bssd`, optionally `scw-bssd-retain`)

## Credentials and secret management

The Scaleway CSI chart supports two configuration modes:

1. Provide credentials directly in Helm values (`controller.scaleway.env`)
2. Reference an **existing Kubernetes Secret** via `controller.scaleway.existingSecretName`

This repo uses the second approach so credentials are not stored in Git.

### Required secret keys

The Kubernetes Secret referenced by `existingSecretName` must contain these keys:

* `SCW_ACCESS_KEY`
* `SCW_SECRET_KEY`
* `SCW_DEFAULT_PROJECT_ID`
* `SCW_DEFAULT_ZONE` (e.g. `nl-ams-1`)
* (optional) `SCW_DEFAULT_REGION` (e.g. `nl-ams`)

VSO is responsible for syncing these keys from Vault into the target namespace.

## Placement

The CSI driver components are pinned to Scaleway nodes:

* Controller: `controller.nodeSelector.cfke.io/provider=scaleway`
* Node plugin: `node.nodeSelector.cfke.io/provider=scaleway`

This ensures the node DaemonSet only runs where Scaleway volumes can attach, and keeps the controller on the same provider.

## Repository layout

Typical files in this folder:

* `helmrepository.yaml`
  Defines the Scaleway Helm repository.

* `helmrelease.yaml`
  Installs the Scaleway CSI chart and pulls values from the generated ConfigMap.

* `scaleway-csi-values.yaml`
  **Plain Helm values file** (not a Kubernetes ConfigMap manifest). Used by `configMapGenerator`.

* `kustomization.yaml`
  Aggregates resources and generates the ConfigMap used by the HelmRelease.

* `secrets/` and/or `vso-config/`
  VSO configuration that results in the `existingSecretName` Secret being present.

## Configuration

### Values file

`scaleway-csi-values.yaml` contains non-secret chart configuration and must set:

```yaml
controller:
  scaleway:
    existingSecretName: "scaleway-csi-secrets"
```

When this is set, the chart will use the VSO-managed Secret and will not rely on default/dummy credentials.

### StorageClass defaults

In a multi-provider cluster, avoid relying on a default StorageClass. Prefer setting `storageClassName` explicitly per workload/overlay:

* Hetzner workloads: `storageClassName: hcloud-volumes`
* Scaleway workloads: `storageClassName: scw-bssd` (or `scw-bssd-retain`)

If default StorageClass behavior is changed, manage it declaratively and ensure only one StorageClass is annotated as default.

## Validation

### Confirm CSI pods are running

```bash
kubectl -n platform get pods -l app.kubernetes.io/name=scaleway-csi -o wide
```

Pods should be scheduled onto the Scaleway node(s).

### Confirm StorageClasses exist

```bash
kubectl get storageclass | grep -E 'scw-|scaleway'
```

### Confirm credentials are being used

If the controller logs indicate an invalid access key format (example defaults like `ABCDEFGHIJKLMNOPQRST`), it means the driver is not reading the intended Secret. Verify:

* `controller.scaleway.existingSecretName` is set in the applied Helm values
* the referenced Secret exists in the same namespace as the HelmRelease
* the Secret contains `SCW_ACCESS_KEY` starting with `SCW...`

## Common pitfalls

### 1) Using a ConfigMap manifest as Helm values

`configMapGenerator.files` must point to a **plain values file**. Do not put `apiVersion/kind/metadata` in `scaleway-csi-values.yaml`. If a ConfigMap manifest is embedded as values, Helm will ignore it and the chart will fall back to defaults.

### 2) Secret name mismatch

The chart will use `controller.scaleway.existingSecretName`. Ensure the Secret name matches exactly and exists in the HelmRelease namespace.

### 3) Two default StorageClasses

If multiple StorageClasses are annotated as default, PVC behavior becomes ambiguous. Prefer explicit `storageClassName` in overlays.

### 4) NodeSelectors that do not match node labels

When pinning workloads by zone, use standard labels such as `topology.kubernetes.io/zone` rather than custom labels that may not exist.

## Operational notes

* Credentials rotation is handled by updating the Vault secret and letting VSO reconcile.
* CSI controller pods typically need a rollout restart to pick up credential changes if injected via env vars.
