# Vault + Kubernetes Auth: A Clear, Correct, Complete Guide

## 1. **How Authentication Works**

### **1.1 What happens when VSO (Vault Secrets Operator) authenticates**

1. A Kubernetes **ServiceAccount** (e.g., `vso-observability`) has a JWT token automatically signed by Kubernetes (or your cluster provider).
2. VSO sends this JWT to Vault endpoint:

   ```
   POST /v1/auth/kubernetes/login
   ```
3. Vault:

   * Validates the JWT’s **issuer**, **audience**, **signature**, and **ServiceAccount identity**.
   * Matches it to a **Vault Kubernetes Role** (NOT RBAC, Vault’s own “role” object).
   * The Role specifies which **Vault Policies** are granted.
4. Vault returns a temporary **Vault Token**.
5. VSO uses that Vault Token to read secrets (per the policies).

---

## 2. **The 4 Required Building Blocks**

### **1. Kubernetes Auth Method**

Enables Vault to accept JWTs from Kubernetes.

### **2. Kubernetes Auth *Config***

Tells Vault how to verify JWTs:

* Kubernetes API host
* CA certificate
* Allowed issuer
* Allowed audience(s)

### **3. Vault Kubernetes *Role***

Maps *“This Kubernetes SA in this namespace”* → *“these Vault policies”*

### **4. Vault *Policies***

Define what paths the SA may read.

These four pieces must match perfectly or auth fails.

---

# Full Setup Instructions

## 3. **Enable Kubernetes Auth Method**

```sh
vault auth enable kubernetes
```

## 4. **Configure the Auth Method**

You must set:

* `kubernetes_host`
* `kubernetes_ca_cert`
* `issuer` (your cluster’s JWT issuer)
* `audience` (optional but recommended)

Example:

```sh
vault write auth/kubernetes/config \
  kubernetes_host="https://10.96.0.1:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  issuer="https://api.cloudfleet.ai/v1/clusters/<cluster-id>" \
  disable_iss_validation=false
```

If your SA tokens require audience validation:

```sh
vault write auth/kubernetes/config \
  pem_keys=[]
```

---

## 5. **Create the Vault Policy**

Example: allow reading KVv2 secrets under `secret/k8s/*`

`vso-operator.hcl`

```hcl
path "secret/data/k8s/*" {
  capabilities = ["read"]
}

path "secret/metadata/k8s/*" {
  capabilities = ["list"]
}
```

Load it:

```sh
vault policy write vso-operator vso-operator.hcl
```

---

## 6. **Create the Vault Kubernetes Role**

This binds Vault to the Kubernetes SA:

```sh
vault write auth/kubernetes/role/vso-observability \
  bound_service_account_names="vso-observability" \
  bound_service_account_namespaces="observability" \
  token_policies="vso-operator" \
  audience="vault" \
  ttl=1h
```

**Important:**
The `audience="vault"` must match the ServiceAccount token configuration used by VSO.
If VSO expects `"vault"`, Vault must expect `"vault"`.

---

## 7. **Create Kubernetes ServiceAccount**

(You already have it, but for completeness.)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vso-observability
  namespace: observability
```

If VSO requires a projected audience token:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vso-observability
  namespace: observability
automountServiceAccountToken: true
```

---

# Verification and Troubleshooting Commands


## 8. **Verify Vault Auth Method**

### Check auth method:

```sh
vault auth list
```

### Check Kubernetes auth config:

```sh
vault read auth/kubernetes/config
```

Look for:

* correct issuer
* correct kubernetes_host
* correct CA
* audience if required

---

## 9. **Check Vault Role**

```sh
vault read auth/kubernetes/role/vso-observability
```

Key things must match:

* `bound_service_account_names`
* `bound_service_account_namespaces`
* `token_policies`
* `audience`

---

## 10. **Check Vault Policy**

```sh
vault policy read vso-operator
```

---

## 11. **Check if Vault can read your secret**

```sh
vault kv get secret/k8s/observability/grafana
```

---

## 12. **Manually Test Authentication**

Run inside Vault pod:

### 12.1 Get a token manually

```sh
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
```

### 12.2 Decode that JWT to inspect issuer + audience

Without jq:

```sh
echo "$TOKEN" | cut -d '.' -f2 | base64 -d 2>/dev/null | sed 's/},{/},\n{/g'
```

Check:

* `"iss"` → must match `auth/kubernetes/config`
* `"aud"` → must include `"vault"` if your role uses audience vault

---

### 12.3 Try logging into Vault USING that token

```sh
vault write auth/kubernetes/login \
  role=vso-observability \
  jwt="$TOKEN"
```

**Success output includes**:

* `token`
* `token_policies ["default" "vso-operator"]`
* proper meta service account fields

If you get:

* **403 service account not authorized** → mismatched SA name or namespace. Or host of the Kubernetes Auth not set to https://kubernetes.default.svc/
* **audience mismatch** → adjust audience in Vault role OR change SA projected audience
* **issuer mismatch** → fix issuer in Vault config

---

# Summary

### To make Kubernetes → Vault auth work, you need:

✔ **Kubernetes Auth Method enabled**
✔ **Kubernetes Auth Method configured to host "https://kubernetes.default.svc/"**
✔ **Kubernetes Auth Config** pointing to API, CA, issuer, audience
✔ **Vault Policy** granting secret paths
✔ **Vault Role** binding the Kubernetes SA → the Policy
✔ **Kubernetes ServiceAccount**
✔ **JWT token with matching issuer & audience**

### And to troubleshoot, you check:

* `vault read auth/kubernetes/config`
* `vault read auth/kubernetes/role/<role>`
* `vault policy read <policy>`
* `vault kv get <path>`
* `decode JWT` and verify audience/issuer
* `vault write auth/kubernetes/login ...` manual test
