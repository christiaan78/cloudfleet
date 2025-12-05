Note: This guide currently describes a manual bootstrap process for Vault. We plan to simplify and automate these steps in a later stage, so treat this as an interim workflow.

# HashiCorp Vault — Setup (Development Cluster)

This guide documents how Vault is installed and initialized on the development cluster using Flux + Helm. It assumes Flux is bootstrapped and the cluster is healthy.

---

## 1) Install Vault via Helm (managed by Flux)

We use the official **hashicorp/vault** Helm chart (installed via a Flux `HelmRelease`). The chart deploys Vault (server + UI) into the cluster.

> Repo: `https://helm.releases.hashicorp.com`  
> Chart: `hashicorp/vault`

Ensure your `HelmRepository` and `HelmRelease` are committed in Git and reconciled by Flux.

---

## 2) Make sure persistent storage is available **before** Vault

Vault needs a **PersistentVolumeClaim** for its storage. If no default StorageClass is present, its PVC will stay **Pending**.

### Option A — Hetzner CSI 
1. Install the **Hetzner Cloud CSI** driver (via HelmRelease). Documentation [here](https://cloudfleet.ai/tutorials/cloud/use-persistent-volumes-with-cloudfleet-on-hetzner/). 
2. Verify a StorageClass exists (e.g., `hcloud-volumes`) and mark it default:
   ```bash
   kubectl get storageclass
   kubectl annotate storageclass hcloud-volumes storageclass.kubernetes.io/is-default-class="true" --overwrite
   ```
3. After this, Vault’s PVC should **bind automatically** and a PV will be created dynamically.

> If you prefer another provisioner (e.g., local-path) or another provider’s CSI, install that first, then return here.

---

## 3) Port-forward to the Vault UI for initialization

Once the hashicorp-vault-agent-injector pod is up, the hashicorp-vault pod will not be ready until the Vault init process is finished. To init Vault, forward the UI port:

```bash
kubectl -n vault get svc
kubectl -n vault port-forward svc/hashicorp-vault 8200:8200
```

Open: **[http://localhost:8200](http://localhost:8200)**

---

## 4) Initialize Vault (Shamir unseal keys)

**Note: even on a HA multi node setup you only have to init on the vault-0 pod**

**Option A:**  
On the UI (or via CLI), click **Initialize** and choose:

* **Key shares (N):** total number of unseal keys to generate  
* **Key threshold (T):** how many of those must be entered to unseal Vault  

> Typical dev values: `N=5`, `T=3`.

**Option B:**  
Initialize using the Vault CLI:
```bash
kubectl -n platform exec -it hashicorp-vault-0 -- \
  env VAULT_ADDR=https://hashicorp-vault.platform.svc:8200 \
  vault operator init -key-shares=2 -key-threshold=2 -tls-skip-verify
```

**Important:** Save the generated **unseal keys** and the **initial root token** securely. They are displayed **once** during init.

---

## 5) Unseal Vault

### 5a) Unseal Vault-0 (Leader) pod:

Enter **T** of the **N** unseal keys until the status changes to **Unsealed**.  
```bash
kubectl -n platform exec -it hashicorp-vault-0 -- sh
```
```bash
vault operator unseal
```

### 5b) Join peers in HA cluster
```bash
kubectl -n platform exec -it hashicorp-vault-1 -- \
  vault operator raft join \
    -leader-ca-cert=@/vault/userconfig/vault-internal-ca/ca.crt \
    https://hashicorp-vault-0.hashicorp-vault-internal:8200
```

### 5c) Unseal the joined pods
```bash
kubectl -n platform exec -it hashicorp-vault-1 -- vault operator unseal
```
---
### 6) Prepare for the bootstrap job to run
```bash
kubectl -n platform exec -it hashicorp-vault-0 --sh
```
```bash
export VAULT_CACERT=/vault/userconfig/vault-server-tls/ca.crt
export VAULT_ADDR=https://hashicorp-vault.platform.svc:8200
export VAULT_TOKEN=<RootTokenProvidedByInit>
```
#### 6a) Create the bootstrap policy:
```bash
  cat <<EOF | vault policy write bootstrap-admin -
# Manage auth backends
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage policies
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage Kubernetes auth config and roles
path "auth/kubernetes/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage userpass users
path "auth/userpass/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

#### 6b) Issue a bootstrap-token bound to that policy
```bash
vault token create -policy=bootstrap-admin -period=24h -renewable=true
```

#### 6c) Store the token in Kubernetes
Manual (outside the pod):
```bash
kubectl -n platform create secret generic vault-bootstrap-token \
  --from-literal=token=<bootstrap-token>
```

#### 6d) Enable secret engine KV v2
```bash
vault secrets enable -path=secret kv-v2
```

### 6e) Enable auth methods
```bash
vault auth enable kubernetes
vault auth enable userpass
```

#### 6f) (Optional) Create a username and password so we can disable the root token but still have admin access
```bash
kubectl -n platform create secret generic vault-bootstrap-user \
  --from-literal=username=<USERNAME> \
  --from-literal=password=<PASSWORD>
```
## 7) Run the bootstrap job
Increment the job version to trigger a new job. 
---
## 8) Verify operator and user accounts can authenticate

- **Manual check with Vault CLI (operator role):**
  ```bash
  vault write auth/kubernetes/login \
      role=vso-operator \
      jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  ```
  This should return a Vault token scoped to the `vso-operator` policy.  
  If you see:
  ```
  * service account name not authorized
  ```
  that’s expected when testing from the vault-cli pod (which uses the `default` SA). It confirms the bootstrap works. The operator pod will succeed once Flux deploys its service account.

- **Manual check with Vault CLI (user account):**
  ```bash
  vault login -method=userpass \
      username=<USERNAME> \
      password="SuperSecret"
  ```
  This should succeed and return a token bound to the `admin` policy.  
  Confirm with:
  ```bash
  vault token lookup
  ```
  You should see `policies: ["admin"]`.

- **Validation in the Vault UI:**
  1. Open the Vault UI (port‑forward or via ingress).  
  2. Choose **“Sign in” → “Username”** and log in with your Userpass account (`<USERNAME>` / `SuperSecret`).  
  3. Confirm that the UI shows your token and attached policies (e.g. `admin`).  
  4. For operator validation, check the Vault UI **Access → Auth Methods → Kubernetes** section to confirm the role exists and is bound correctly. The operator itself will authenticate automatically once Flux deploys it.

**Enable KV secrets engine and create Grafana policy/role:**

```bash
vault secrets enable -path=secret kv-v2 || echo "KV already enabled"

cat <<EOF | vault policy write grafana -
path "secret/data/grafana" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/grafana \
    bound_service_account_names=grafana \
    bound_service_account_namespaces=platform \
    policies=grafana \
    ttl=24h \
    audience="<aud-from-token>"
```
---
## 8) Cleanup

Once bootstrap is complete:

- **Disable the root token** (so it cannot be used accidentally):
  ```bash
  vault token revoke <ROOT_TOKEN>
  ```
  > Keep the unseal keys and root token securely stored, but revoke the active root token used during bootstrap.

- **Exit the vault-cli pod:**
  ```bash
  exit
  ```

- **Delete the vault-cli pod:**
  ```bash
  kubectl -n platform delete pod vault-cli
  ```

This ensures you’re no longer relying on the root token or temporary CLI pod, and only Flux‑managed resources remain active.

## Troubleshooting
- **PVC Pending:** ensure a default StorageClass exists.  
- **Cannot reach UI:** confirm port-forward is active.  
- **Unseal prompts keep appearing:** all pods must be unsealed; consider HA vs standalone mode.
- **Raft joining fails:** If Raft join fails with x509: certificate is valid for … not …, check SANs in the mounted cert.

---