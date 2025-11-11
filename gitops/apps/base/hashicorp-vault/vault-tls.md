# Vault TLS (in-cluster) & Traefik upstream TLS

## What we’re trying to achieve (and why)

We want a **secure-by-default** platform where:

1. **All in-cluster traffic to Vault is HTTPS.**
   Clients inside Kubernetes (ESO, platform, CLI, probes) connect to
   `https://hashicorp-vault.platform.svc:8200`, and **validate** Vault’s identity.

2. **Certificates are managed declaratively.**
   Certificates are issued automatically by **cert-manager**, not by hand, and live in Git (through CRDs, not raw key material).

3. **Ingress is safe for demos & day-2.**
   Traefik reverse proxy **terminates at the edge**, but when it speaks to Vault it also uses **HTTPS upstream** and **verifies** Vault’s cert with a trusted CA—no “insecure” hops inside the cluster.

This gives us encrypted, verified traffic end-to-end, reproducible with Flux, and portable across providers.

---

## How it works (high level)

### 1) Certificates (cert-manager)

* We bootstrap a **self-signed CA** just once for the cluster (`vault.internal.ca`).
* Using that CA, cert-manager issues a **server certificate** for Vault with DNS SANs that match the service names:

  * `hashicorp-vault.platform.svc`
  * `hashicorp-vault.platform.svc.cluster.local`
* cert-manager stores:

  * the **CA** in a Secret (`platform/vault-internal-ca`)
  * the **server cert** in a Secret (`platform/vault-server-tls`)

### 2) Vault server (Helm)

* Vault mounts `vault-server-tls` into the pod and configures its **listener** to use `tls.crt`, `tls.key`, and `ca.crt`.
* We set `VAULT_CACERT` so the pod itself (and CLI/probes) trusts the same CA.
* Readiness/liveness probes are adjusted to avoid false negatives while TLS is coming up.

### 3) Traefik → Vault (upstream TLS)

* Traefik gets a **ServersTransport** object that says:

  * “When I call Vault, use SNI `hashicorp-vault.platform.svc` and trust this **CA**.”
* We provide that CA to Traefik via a Secret (`ingress-traefik/vault-ca`) containing **`ca.crt`**.
  *(For the PoC we keep this Secret **static** with the CA public cert—simple and explicit.)*
* On the **Vault Service**, we add Traefik annotations telling it to:

  * use **HTTPS** upstream, and
  * use that **ServersTransport**.

Result: **Browser → Traefik (edge)**, and **Traefik → Vault (HTTPS, verified)**.

---

## The GitOps implementation (where everything lives)

### A) Cert-manager (installed once)

* `gitops/infrastructure/base/cert-manager/`
  Helm repo + HelmRelease + kustomization.
* `gitops/infrastructure/development/cert-manager/`
  Overlay + `namespace.yaml`.

### B) Vault TLS (certificates issued by cert-manager)

* `gitops/infrastructure/base/tls/vault/`

  * `issuer-selfsigned.yaml` (bootstrap Issuer)
  * `certificate-internal-ca.yaml` (**creates** `platform/vault-internal-ca` – the CA)
  * `issuer-internal-ca.yaml` (Issuer backed by that CA)
  * `certificate-vault-server.yaml` (**creates** `platform/vault-server-tls` – Vault server cert)
  * `kustomization.yaml`
* `gitops/infrastructure/development/tls/vault/`
  Overlay `kustomization.yaml` that applies the above in dev.

> **Reconcile order:** the TLS overlay must run **before** Vault so the Secrets exist when Helm renders the StatefulSet. Your `clusters/development/infrastructure-tls-vault-development.yaml` handles that.

### C) Vault (the app)

* `gitops/platform/base/hashicorp-vault/`

  * `helmrepository.yaml` (HashiCorp charts)
  * `helmrelease.yaml` (chart `vault`)
  * `kustomization.yaml`
* `gitops/platform/development/hashicorp-vault/`

  * `namespace.yaml` (namespace `platform`)
  * `values.yaml` (**TLS mount & listener**, `VAULT_CACERT`, probe overrides, and **Service annotations for Traefik**; see below)
  * `ingress.yaml` (Traefik class & host rules only)
  * `kustomization.yaml` (includes the above and wires values into the HelmRelease)

**Key values you set in `values.yaml`:**

* Mount `vault-server-tls` and point the listener at:

  * `/vault/userconfig/vault-server-tls/tls.crt`
  * `/vault/userconfig/vault-server-tls/tls.key`
  * `/vault/userconfig/vault-server-tls/ca.crt`
* `extraEnvironmentVars.VAULT_CACERT` → same CA path
* Probe overrides (use `-tls-skip-verify` inside the probe shell to avoid early failures)
* **Service annotations** (this is where Traefik learns to use upstream TLS + the ServersTransport):

  * `traefik.ingress.kubernetes.io/service.serversscheme: https`
  * `traefik.ingress.kubernetes.io/service.serverstransport: ingress-traefik-vault-tls@kubernetescrd`

### D) Traefik (the ingress controller)

* `gitops/platform/base/traefik/`

  * `helmrelease-traefik.yaml`, `helmrelease-crds.yaml`, `helmrepository.yaml`, `kustomization.yaml`
* `gitops/platform/development/traefik/`

  * `kustomization.yaml`, `namespace.yaml`
  * `serverstransport-vault.yaml` (**ServersTransport** with `serverName: hashicorp-vault.platform.svc` and `rootCAs: - secret: vault-ca`)
  * `vault-ca-secret.yaml` (**static** Secret with `ca.crt` for Traefik to trust the Vault CA)
  * `patch-helmrelease-values.yaml` (enables `providers.kubernetesCRD.allowCrossNamespace: true` so the Service in `platform` can reference a ServersTransport in `ingress-traefik`)

> **Why cross-namespace?**
> Our Service (in `platform`) points to a ServersTransport located in `ingress-traefik`. The Traefik chart flag `providers.kubernetesCRD.allowCrossNamespace: true` enables that reference.

### E) Cluster wiring (Flux)

* `gitops/clusters/development/`

  * `infrastructure-cert-manager-development.yaml`
  * `infrastructure-storage-hcloud-csi-development.yaml`
  * `infrastructure-tls-vault-development.yaml`  **→ must reconcile before Vault**
  * `platform-hashicorp-vault-development.yaml`
  * `platform-traefik-development.yaml`
  * `platform-kube-prometheus-stack-development.yaml`
  * `platform-podinfo-development.yaml`

Order is enforced with `dependsOn` (or by sequencing the infra Kustomizations before the platform).

### F) Local demo access

* `tools/scripts/port-forwarding/port-forward.sh`
  Port-forwards Traefik’s Service (e.g., `:18443 → :443`) and auto-kills stale forwards.
  Add `development.vault.internal` in `/etc/hosts` → browse `https://development.vault.internal:18443/`.

---

## Traffic flows (end-to-end)

### In-cluster clients → Vault

1. Client resolves `hashicorp-vault.platform.svc` via kube-DNS.
2. TLS handshake to Vault pod with the **server cert** issued by our **internal CA**.
3. Client validates cert using the **CA** (`VAULT_CACERT` path or mounted trust).
4. Requests proceed over **HTTPS**.

### Browser → Traefik → Vault

1. Browser hits `development.vault.internal` (port-forwarded to Traefik).
2. Traefik routes to Service `hashicorp-vault` in `platform`.
3. Because the Service carries **Traefik service annotations**, Traefik:

   * uses **HTTPS upstream**
   * uses the **ServersTransport** `vault-tls` (SNI `hashicorp-vault.platform.svc`, trust bundle **`vault-ca`** Secret)
4. Traefik **validates** Vault’s cert before proxying the request.

---

## Validation checklist (quick)

* **Secrets exist**
  `platform/vault-internal-ca` (CA) and `platform/vault-server-tls` (server) both present with data; Traefik’s `ingress-traefik/vault-ca` has **`ca.crt`**.

* **Vault mounted & listening with TLS**
  Pod mounts `/vault/userconfig/vault-server-tls/…` and `listener "tcp"` uses those paths with `tls_disable = 0`.

* **Service annotations present**
  `kubectl -n platform get svc hashicorp-vault -o yaml` shows:

  * `traefik.ingress.kubernetes.io/service.serversscheme: https`
  * `traefik.ingress.kubernetes.io/service.serverstransport: ingress-traefik-vault-tls@kubernetescrd`

* **ServersTransport present**
  In `ingress-traefik`: `serverstransport.vault-tls` with:

  * `serverName: hashicorp-vault.platform.svc`
  * `rootCAs: - secret: vault-ca`

* **Traefik chart flag set**
  `providers.kubernetesCRD.allowCrossNamespace: true` is applied.

---

## Role of cert-manager

cert-manager is the **certificate authority fabric** of the cluster:

* Issues and renews the **internal CA** (for Vault) and the **Vault server certificate**.
* Keeps Secrets up to date so workloads (Vault, Traefik) always have valid material.
* Lets us describe PKI as Kubernetes resources (Issuer/Certificate) versioned in Git and reconciled by Flux—no manual openssl, no one-off secrets.

> For Traefik’s CA trust, we intentionally use a **static Secret** (`ingress-traefik/vault-ca`) that contains the CA’s public cert (`ca.crt`). This is simple, explicit, and portable across environments. (We tried cross-namespace injection; for this PoC the static Secret is clearer and more predictable.)

---

## Common pitfalls (what to avoid)

* **Putting Traefik’s “service.*” on the Ingress instead of the Service.**
  Those options are **service-level** for the Kubernetes Ingress provider; set them on the **Vault Service** (we do this via Vault Helm values).

* **Not enabling cross-namespace CRD references in Traefik.**
  Without `providers.kubernetesCRD.allowCrossNamespace: true`, a Service in `platform` cannot use a ServersTransport in `ingress-traefik`.

* **Traefik CA Secret missing `ca.crt`.**
  Traefik expects the key to be **`ca.crt`** (or `tls.ca`). If it’s empty/incorrect, Traefik will fall back to IP and you’ll see “x509: cannot validate certificate for 10.x.x.x because it doesn’t contain any IP SANs”.

* **Vault server cert missing the right SANs.**
  The server Certificate **must** include `hashicorp-vault.platform.svc` (and `.svc.cluster.local`). Otherwise SNI validation fails.

* **Reconcile order.**
  Ensure the TLS overlay (cert-manager + CA + server Certificate) applies **before** Vault, so the Secrets exist when the StatefulSet renders.

* **Local port collisions.**
  If port-forwards fail with “address already in use”, kill stale `kubectl port-forward` processes (our script does this automatically).
