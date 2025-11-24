# 🔐 Vault Cheatsheet

A quick reference for HashiCorp Vault commands, concepts, and workflows.

---

## 📦 Secret Engines
- **List enabled engines**
  ```bash
  vault secrets list -detailed
  ```
- **Enable KV v2 at `secret/`**
  ```bash
  vault secrets enable -path=secret kv-v2
  ```
- **Write a secret**
  ```bash
  vault kv put secret/k8s/namespace/secretname \
  username="username" \
  password="supersecret"
  ```
- **Read a secret**
  ```bash
  vault kv get secret/<path>
  ```
- **Delete a secret**
  ```bash
  vault kv delete secret/<path>
  ```

---

## 🔑 Auth Methods
- **List enabled auth methods**
  ```bash
  vault auth list -detailed
  ```
- **Enable Kubernetes auth**
  ```bash
  vault auth enable kubernetes
  ```
- **Configure Kubernetes auth**
  First get the issuer and the cluster aud. From a pod within the cluster (e.g. debug pod):
  ```bash
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)
  echo $PAYLOAD | base64 -d | jq .
  ```
Than configre the Kubernetes Auth method:
  ```bash
  vault write auth/kubernetes/config \
      kubernetes_host="https://<apiserver>:443" \
      kubernetes_ca_cert=@ca.crt \
      token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
      issuer="value from previous command" \
      audiences="<value you saw>"
  ```
- **Enable userpass auth**
  ```bash
  vault auth enable userpass
  ```
- **Create userpass user**
  ```bash
  vault write auth/userpass/users/<username> \
      password=<password> \
      policies=<policy>
  ```

---

## 📜 Policies
- **Write a policy**
  ```bash
  cat <<EOF | vault policy write <name> -
  path "secret/data/<namespace>/*" {
    capabilities = ["read"]
  }
  path "secret/metadata/<namespace>/*" {
    capabilities = ["list"]
  }
  EOF
  ```
- **List policies**
  ```bash
  vault policy list
  ```
- **Read a policy**
  ```bash
  vault policy read <name>
  ```

---

## 🎟️ Tokens
- **Login with userpass**
  ```bash
  vault login -method=userpass username=<user> password=<pass>
  ```
- **Lookup current token**
  ```bash
  vault token lookup
  ```
- **Revoke a token**
  ```bash
  vault token revoke <token>
  ```
- **Generate one-time root token**
  ```bash
  vault operator generate-root -init -format=json
  ```

---

## ⚙️ Operator Commands
- **Status**
  ```bash
  vault status
  ```
- **Seal / Unseal**
  ```bash
  vault operator seal
  vault operator unseal
  ```
- **Enable audit logging**
  ```bash
  vault audit enable file file_path=/var/log/vault_audit.log
  ```

---

## 🧩 Useful Patterns
- **Idempotent enable**
  ```bash
  vault secrets enable -path=secret kv-v2 || echo "KV already enabled"
  vault auth enable kubernetes || echo "Auth already enabled"
  ```
- **Hierarchical secret paths**
  ```
  secret/<team>/<app>/<component>
  ```
  Example: `secret/observability/grafana`

---
