# Vault TLS (in-cluster) & Traefik upstream TLS

## What we’re trying to achieve (and why)

We want a **secure-by-default** platform where:

1. **All in-cluster traffic to Vault is HTTPS.**  
   Clients inside Kubernetes (ESO, platform, CLI, probes) connect to  
   `https://hashicorp-vault.platform.svc:8200`, and **validate** Vault’s identity.

2. **Vault peers also communicate securely.**  
   Raft storage requires Vault pods (`vault-0`, `vault-1`, `vault-2`) to talk to each other over TLS.  
   Certificates must include **SANs for both service names and pod DNS names** so that peer-to-peer TLS handshakes succeed.

3. **Certificates are managed declaratively.**  
   Certificates are issued automatically by **cert-manager**, not by hand, and live in Git (through CRDs, not raw key material).

4. **Ingress is safe.**  
   Traefik reverse proxy **terminates at the edge**, but when it speaks to Vault it also uses **HTTPS upstream** and **verifies** Vault’s cert with a trusted CA—no “insecure” hops inside the cluster.

This gives us encrypted, verified traffic end-to-end, reproducible with Flux, and portable across providers.

---

## How it works (high level)

### 1) Certificates (cert-manager)

* We bootstrap a **self-signed CA** just once for the cluster (`vault.internal.ca`).
* Using that CA, cert-manager issues a **server certificate** for Vault with DNS SANs that match:
  * Service names:
    * `hashicorp-vault.platform.svc`
    * `hashicorp-vault.platform.svc.cluster.local`
  * Pod DNS names:
    * `hashicorp-vault-0.hashicorp-vault-internal`
    * `hashicorp-vault-1.hashicorp-vault-internal`
    * `hashicorp-vault-2.hashicorp-vault-internal`
  * Loopback (`127.0.0.1`) for CLI inside pods.
* cert-manager stores:
  * the **CA** in a Secret (`platform/vault-internal-ca`)
  * the **server cert** in a Secret (`platform/vault-server-tls`)

---

## Role of each file (`crt`, `key`, `ca`)

- **`tls.crt` (certificate)**  
  Public certificate presented by Vault during TLS handshake.  
  Contains the SANs (service names, pod DNS names, IPs) that clients and peers validate against.

- **`tls.key` (private key)**  
  Private key corresponding to `tls.crt`.  
  Used by Vault to prove ownership of the certificate during handshake. Must remain secret.

- **`ca.crt` (certificate authority)**  
  Public certificate of the internal CA that issued `tls.crt`.  
  Clients (CLI, ESO, Traefik, Vault peers) use this to verify that Vault’s certificate is trusted.

👉 In short:  
- `tls.crt` = Vault’s identity card.  
- `tls.key` = Vault’s private signature pen.  
- `ca.crt` = The trusted authority that validates the identity card.

---

### 2) Vault server (Helm)

* Vault mounts `vault-server-tls` into the pod and configures its **listener** to use `tls.crt`, `tls.key`, and `ca.crt`.
* We set `VAULT_CACERT` so the pod itself (and CLI/probes) trusts the same CA.
* Readiness/liveness probes are adjusted to avoid false negatives while TLS is coming up.
* Raft peers use the same cert bundle to authenticate each other — SANs must include pod DNS names or peer joins will fail.

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

> **Reconcile order:** the TLS overlay must run **before** Vault so the Secrets exist when Helm renders the StatefulSet. The `clusters/development/infrastructure-tls-vault-development.yaml` handles that.

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
  * `platform-vault-development.yaml`
  * `platform-traefik-development.yaml`
  * `platform-kube-prometheus-stack-development.yaml`
  * `platform-podinfo-development.yaml`

Order is enforced with `dependsOn` (or by sequencing the infra Kustomizations before the platform).

### F) Local access

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

### Vault peers → Vault peers (Raft)

1. Vault‑1 resolves `hashicorp-vault-0.hashicorp-vault-internal` via kube-DNS.  
2. TLS handshake between Vault‑1 and Vault‑0 using the same **server cert**.  
3. Peer validates cert using the **CA** and checks SANs include the pod DNS name.  
4. Raft replication proceeds securely over **HTTPS**.

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

## Common pitfalls

* **Vault peer cert missing pod SANs.**  
  Raft join fails with `x509: certificate is valid for … not …` if SANs don’t include pod DNS names. Always include both service names and pod DNS names.

* **Confusing cert roles.**  
  Remember: `tls.crt` is what Vault shows, `tls.key` is what Vault proves, `ca.crt` is what everyone else trusts.

