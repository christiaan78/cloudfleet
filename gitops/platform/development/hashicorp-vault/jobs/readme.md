# Jobs Directory

This folder contains Kubernetes Job manifests used to **bootstrap HashiCorp Vault** in the cluster.  
The jobs run once to configure Vault authentication methods, policies, and roles in a GitOps‑friendly way.

## What these jobs do
- Enable and configure the Kubernetes auth method.
- Create namespace‑scoped Vault policies (e.g. `observability`, `apps`, `platform`).
- Bind policies to Vault roles used by the Vault Secrets Operator (VSO).
- Optionally create a userpass admin account for manual access.

## Workflow 
1. **Follow the steps** in platform/base/hashicorp-vault Readme to initialize Vault and perform the actions that can only done with a root token. 
2. **Run the Job** by incrementing the job version number. 
   - The Job uses the token and script to configure Vault.
   - Logs show `Bootstrap complete.` when successful.

## Adding a new namespace
When you need Vault Secrets Operator access for a new namespace:
1. Edit the `bootstrap.sh` script in the ConfigMap to add a new policy stanza:
   ```hcl
   path "secret/data/<namespace>/*" {
     capabilities = ["read"]
   }
   path "secret/metadata/<namespace>/*" {
     capabilities = ["list"]
   }
   ```
2. Commit and push the updated ConfigMap to Git.
3. Re‑run the bootstrap Job:
   - Either delete the old Job (`kubectl delete job vault-bootstrap-job -n platform`)  
   - Or bump the Job name (e.g. `vault-bootstrap-job-v2`) so Flux applies it again.
4. Verify the Job completes and the new policy is active in Vault.

## Notes
- **Secrets**: Sensitive values (like bootstrap token, userpass credentials) are stored in Kubernetes Secrets, not in Git.
- **Idempotency**: Policies and roles are overwritten if they already exist, so Jobs are safe to re‑run.
- **Future migration**: Terraform Vault provider can replace these Jobs for fully declarative policy management.
```
