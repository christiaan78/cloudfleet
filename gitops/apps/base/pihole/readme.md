# Pi-hole (Multi-Provider Deployment via Flux/Kustomize)

This folder contains the GitOps configuration for deploying **two independent Pi-hole instances** on a single Kubernetes cluster spanning **Hetzner** and **Scaleway** nodes. The deployment is managed with **Flux** and **Kustomize overlays** and is designed to demonstrate provider-aware placement, provider-specific storage, and shared secret management via Vault.

## Objectives

* Run **Pi-hole in two providers** (Hetzner + Scaleway) in the same cluster.
* Control **workload placement** (provider/zone) per instance.
* Use **provider-specific storage** (Hetzner volumes on Hetzner nodes; Scaleway volumes on Scaleway nodes).
* Keep **Vault authentication shared**, while **secrets are instance-specific**.
* Expose DNS and UI access via **Tailscale**.

## Repository structure

### Base (`gitops/apps/base/pihole`)

The base is intentionally split into two parts:

#### `common/` (shared, deployed once)

Resources that must exist only once in the `pihole` namespace:

* `ServiceAccount` for VSO (`vso-pihole`)
* `VaultAuth` (`pihole-vault-auth`) referencing the global Vault auth configuration
* Any other shared/non-instance resources

This avoids duplication and prevents issues where provider overlays accidentally create prefixed copies (e.g. `htz-pihole-vault-auth`).

#### `app/` (instanceable, deployed per provider)

Resources that are deployed once per provider instance (and typically prefixed by the overlay):

* Pi-hole `Deployment`
* Services (`ClusterIP` and Tailscale `LoadBalancer`)
* Ingress (Tailscale ingress class)
* Bootstrap job (if present)
* NetworkPolicies (if present)

The base `app` is provider-agnostic; provider overlays supply:

* placement rules
* storage class selection
* instance-specific secrets
* any provider-specific hostname/ingress adjustments

### Development overlays (`gitops/apps/development/pihole`)

The development environment deploys **both** provider instances:

* `hetzner/`
* `scaleway/`

A parent `kustomization.yaml` typically composes:

* `../../base/pihole/common`
* `./hetzner`
* `./scaleway`

Each provider overlay:

* applies a `namePrefix` (e.g. `htz-`, `scw-`)
* adds instance labels (e.g. `pihole.instance: hetzner|scaleway`)
* patches Deployment/PVC/Ingress/Tailscale resources
* adds a provider-specific `VaultStaticSecret` that materializes an instance-specific Kubernetes Secret

## Instance separation model

Each Pi-hole instance is treated as independent:

* Separate Kubernetes resource names via `namePrefix`
* Separate PVCs (provider-specific StorageClass)
* Separate password secrets (provider-specific Vault paths)

This enables:

* independent lifecycle and troubleshooting
* avoiding cross-provider storage assumptions
* reducing blast radius (one instance can break without impacting the other)

## Scheduling and placement

Provider overlays control placement using node selectors. At minimum:

* `cfke.io/provider: hetzner` for the Hetzner instance
* `cfke.io/provider: scaleway` for the Scaleway instance

For zone pinning, prefer standard Kubernetes topology labels, for example:

* `topology.kubernetes.io/zone: nl-ams-1`

Avoid relying on custom labels that may not exist on nodes (e.g. `cfke.io/zone`), unless they are guaranteed by the node provisioning process.

## Storage

Pi-hole uses a PVC for `/etc/pihole` (or the chosen persistent path). Storage must be provider-specific:

* Hetzner instance uses `hcloud-volumes`
* Scaleway instance uses a Scaleway StorageClass (e.g. `scw-bssd`)

In a multi-provider cluster, do not assume a default StorageClass will be correct for all workloads. Prefer setting `storageClassName` explicitly in each overlay PVC patch.

## Secrets (Vault + VSO)

### Shared VaultAuth

A single `VaultAuth` (`pihole-vault-auth`) is deployed in `base/pihole/common`. It references the VSO global auth configuration and is reused by both provider instances.

### Instance-specific VaultStaticSecret

Each provider overlay defines its own `VaultStaticSecret`:

* Hetzner: creates `htz-pihole-webpassword` from a Hetzner-specific Vault path
* Scaleway: creates `scw-pihole-webpassword` from a Scaleway-specific Vault path

Each Pi-hole Deployment overlay patches:

* `FTLCONF_webserver_api_password.secretKeyRef.name` to the instance secret (`htz-...` / `scw-...`)

This prevents ownership conflicts and avoids controllers fighting over the same destination Secret.

## Networking and access

### ClusterIP Service

Each instance exposes:

* HTTP UI on port 80
* DNS on port 53 TCP/UDP

### Tailscale LoadBalancer (DNS)

Each instance exposes DNS via a Tailscale `LoadBalancer` Service (`loadBalancerClass: tailscale`), typically with an instance-specific hostname annotation.

### Tailscale Ingress (UI)

Each instance exposes the UI via `Ingress` using the Tailscale ingress class.

## Validation checklist

### Verify both instances are running

```bash
kubectl -n pihole get deploy
kubectl -n pihole get pods -o wide
```

### Verify Services have endpoints

```bash
kubectl -n pihole get svc
kubectl -n pihole get endpoints
```

### Verify secrets exist per instance

```bash
kubectl -n pihole get secret | grep webpassword
kubectl -n pihole get vaultstaticsecret
```

### Verify placement

```bash
kubectl -n pihole get pods -o wide
```

Pods should be scheduled to the intended provider nodes.

### Verify PVC provisioning

```bash
kubectl -n pihole get pvc
kubectl get storageclass
```

PVCs for each instance should bind using the correct provider StorageClass.

## Common pitfalls

### 1) Kustomize `namePrefix` applied to shared resources

If shared resources (e.g. `VaultAuth`) are included in a prefixed overlay, Kustomize will rename them and introduce duplicate/incorrect resources. Keep shared VSO config in `common/` and do not apply prefixes there.

### 2) Duplicate Namespace resources

If multiple overlays include a `Namespace` manifest for `pihole`, Kustomize build will fail due to duplicate cluster-scoped IDs. Define the namespace once (or manage it outside this app tree).

### 3) Services without endpoints

If a Service has no endpoints, it usually means the pod did not schedule (nodeSelector/zone mismatch) or the selector labels do not match the pod labels.

### 4) Secret references are not auto-renamed

Kustomize does not automatically rewrite string literals in env vars such as `secretKeyRef.name`. Overlay patches must update the secret name for each instance.

## Notes on provider outage and redundancy

This setup provides resilience by running two independent DNS endpoints in two providers. It does not provide shared persistent state across providers (that would require a distributed storage layer such as Longhorn or Ceph, which is tracked separately as a roadmap item).
