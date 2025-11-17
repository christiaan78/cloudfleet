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
# Replace namespace if different
kubectl -n vault get svc
# Example shows:
# NAME             TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)              AGE
# hashicorp-vault  ClusterIP   10.97.17.231   <none>        8200/TCP,8201/TCP    5m

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
> In production choose values that match your operational model and key custodians.

**Option B:**
Initialize using the Vault CLI (edit the key shares and threshold to a value that works for your project):
```
kubectl -n platform exec -it hashicorp-vault-0 --   env VAULT_ADDR=https://hashicorp-vault.platform.svc:8200   vault operator init -key-shares=2 -key-threshold=2 -tls-skip-verify
```


**Important:** Save the generated **unseal keys** and the **initial root token** in a secure place (password manager / HSM-backed secret store). They are displayed **once** during init.


---

## 5) Unseal Vault

After initialization, Vault is still **sealed**. Enter **T** of the **N** unseal keys one-by-one (UI prompts for each) until the status changes to **Unsealed**.

You must repeat unseal on each Vault pod (if running HA) or when pods restart (unless using auto-unseal with a KMS, which is out of scope for this phase).

---

## 6) Log in with the root token

Once unsealed, log in using the **root token** shown during initialization.

* In the UI: choose “Token” method and paste the root token
* Or via CLI (if configured):

  ```bash
  export VAULT_ADDR=http://localhost:8200
  vault login <ROOT_TOKEN>
  ```

Perfect, Christiaan — let’s extend your README with the next steps we’ve been working through. I’ll keep the style consistent with your existing documentation and add the commands and context we discussed.

---

## 7) Setup Vault CLI and test connection

Install the Vault CLI on your workstation:  
👉 [Download instructions](https://developer.hashicorp.com/vault/install#linux)

To connect from outside the cluster, use **port‑forwarding**:

```bash
kubectl -n platform port-forward svc/hashicorp-vault 8200:8200
```

Then configure your environment:

```bash
# Point Vault CLI to the forwarded port
export VAULT_ADDR=https://127.0.0.1:8200

# Extract the CA certificate from the vault-internal-ca secret
kubectl -n platform get secret vault-internal-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > vault-ca-chain.crt

# Tell Vault CLI to trust this CA
export VAULT_CACERT=$(pwd)/vault-ca-chain.crt

# Login with your root token (from init)
vault login <ROOT_TOKEN>
```

Validate connectivity:

```bash
vault status
```

---

  ## 8) Enable Kubernetes auth and create policies/roles

  Use the root token only for bootstrap. Once Kubernetes auth is enabled, workloads will authenticate via service accounts.

  ### a) Enable Kubernetes auth
  ```bash
  vault auth enable kubernetes
  ```

  ### b) Configure Kubernetes auth
  ```bash
  vault write auth/kubernetes/config \
      kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
      kubernetes_ca_cert=@vault-ca-chain.crt \
      token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
  ```

  ### c) Create an admin policy (example)
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
  Enable the Userpass auth method (if not already enabled):

  ```bash
  vault auth enable userpass
  ```
  Create a user bound to the admin policy:

  ```bash
  vault write auth/userpass/users/<CHANGEUSERNAME> \
      password="SuperSecret" \
      policies=admin
  ```
  Now you can log into the Vault UI with:

  Username: <USERNAME>

  Password: SuperSecret

  Policy: admin (full rights)

  ### e) Create the operator policy (example)
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

  ### f) Create the operator role bound to the operator’s service account
  ```bash
  vault write auth/kubernetes/role/vso-operator \
      bound_service_account_names=hashicorp-vault-secrets-operator-controller-manager \
      bound_service_account_namespaces=platform \
      policies=vso-operator \
      ttl=24h
      audience="vault"
  ```

---

## 9) Verify operator and workloads can authenticate

Before deploying the CRDs (`VaultConnection` and `VaultAuth`):

- **Manual check with Vault CLI:**
  ```bash
  vault write auth/kubernetes/login \
      role=vso-operator \
      jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  ```
  This should return a Vault token scoped to the `vso-operator` policy.

- **Operator logs:**  
  Once you deploy the CRDs, check the operator logs to confirm it authenticates successfully.

---

## ✅ Summary of bootstrap additions
- Step 7: Install Vault CLI, port‑forward, configure CA, test with `vault status`.  
- Step 8: Use root token to enable Kubernetes auth, create admin + operator policies/roles.  
- Step 9: Verify authentication manually before deploying CRDs.  

---

👉 Would you like me to also add a **“Best Practices” section** at the end of the README (e.g., root token usage, short‑lived bootstrap tokens, revocation after bootstrap), so your dev cluster doc already nudges toward production‑grade habits?

---

## Troubleshooting

* **PVC Pending / no PV:** check `kubectl get sc` and ensure a default StorageClass is present; install CSI first.
* **Cannot reach UI:** confirm `port-forward` is active and service name/namespace is correct.
* **Unseal prompts keep appearing:** all pods must be unsealed; consider HA vs standalone mode and restarts.


