Note: This guide currently describes a manual bootstrap process for Vault. We plan to simplify and automate these steps in a later stage, so treat this as an interim workflow.

Disclaimer: This README was drafted with the assistance of AI and will be reviewed and validated before use in production.

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

Enter **T** of the **N** unseal keys until the status changes to **Unsealed**.  
Repeat on each Vault pod (if HA) or after restarts (unless using auto-unseal).

---

**THE BELOW STEPS ARE THE MANUAL STEPS FOR A MINIMAL BOOTSTRAP. INSTEAD, THE BOOTSTRAP CAN ALSO BE PERFORMED BY THE SCRIPT PROVIDED IN TOOLS >> MANIIFESTS >> VAULT-BOOTSTRAP**

---

When you are not using the bootstrap script, continue with the steps below:

## 6) Setup Vault CLI and test connection

Instead of installing Vault CLI locally, use the **vault-cli pod** stored in your repo under `/tools/manifests/vault-cli.yaml`. Apply it:

```bash
kubectl apply -f tools/manifests/vault-cli.yaml
kubectl -n platform exec -it vault-cli -- sh
```

Inside the pod:

```bash
export VAULT_ADDR=https://hashicorp-vault.platform.svc:8200
export VAULT_CACERT=/vault/ca/ca.crt
vault login <ROOT_TOKEN>
vault status
```

---

## 7) Enable Kubernetes auth and create policies/roles

Use the root token only for bootstrap.

### a) Enable Kubernetes auth
```bash
vault auth enable kubernetes
```

### b) Configure Kubernetes auth
```bash
vault write auth/kubernetes/config \
    kubernetes_host="https://<apiserver-host>:443" \
    kubernetes_ca_cert=@/vault/ca/ca.crt \
    token_reviewer_jwt=@/reviewer.jwt
```

### c) Create an admin policy
Save as `admin.hcl`:
```hcl
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
```
Load it:
```bash
vault policy write admin admin.hcl
```

### d) Create an admin user (Userpass)
```bash
vault auth enable userpass
vault write auth/userpass/users/<USERNAME> \
    password="SuperSecret" \
    policies=admin
```

### e) Create the operator policy
Save as `vso-operator.hcl`:
```hcl
path "secret/*" {
  capabilities = ["read", "list"]
}
```
Load it:
```bash
vault policy write vso-operator vso-operator.hcl
```

### f) Extract token and audience, then create operator role
First, extract the token and decode the audience (this differs per cluster):
```bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)
echo "$PAYLOAD" | base64 -d
```
Note the `"aud"` value.

Then create the role:
```bash
vault write auth/kubernetes/role/vso-operator \
    bound_service_account_names=hashicorp-vault-secrets-operator-controller-manager \
    bound_service_account_namespaces=platform \
    policies=vso-operator \
    ttl=24h \
    audience="<aud-from-token>"
```

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
## 9) Cleanup

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

---