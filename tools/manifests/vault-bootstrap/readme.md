# Bootstrap Vault

To bootstrap Vault with a minimal configuration with a userpass account and Vault Secrets Operator role: 

1. Follow the steps 1 to 5 outlined in the readme.md in the hashicorp-vault base folder. **Store the keys and token in a secure place!***
2. Update the bootstrap file with a USERNAME and PASSWORD 
3. Apply the vault-cli-bootstrap-script.yaml:

```bash
kubectl apply -f vault-cli-with-bootstrap.yaml
```

4. Exec into the pod:

```bash
kubectl -n platform exec -it vault-cli -- sh
```

5. Export your root token (provided after Vault init proces)

```bash
export VAULT_ADDR=https://hashicorp-vault.platform.svc:8200
export VAULT_CACERT=/vault/ca/ca.crt
export VAULT_TOKEN=<ROOT_TOKEN>
```

6. Run the bootstrap script

```bash
/scripts/bootstrap.sh
```