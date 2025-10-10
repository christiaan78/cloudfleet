# Cloudfleet Multi-Cloud Kubernetes Cluster

## Cloudfleet setup

<div style="border-left: 4px solid #1e90ff; background-color: #eaf4ff; padding: 0.75em 1em; border-radius: 4px; color: #1a1a1a;">
<strong>ℹ️ Info:</strong> Clusters of the type "Basic" offer free control planes. You only pay for the worker nodes provisioned at the provider of your choice. Read more about this on <a href="https://cloudfleet.ai/pricing" target="_blank" rel="noopener noreferrer">Cloudfleet pricing</a>.
</div>

<br>


Create an account at cloudfleet.ai and follow the instructions to add a cluster and connect to it from your workstation. Easiest way to get started is using a cloud provider that offers auto provisioning like Hetzner. 


## Flux setup
### Install the Flux CLI
The flux command-line interface (CLI) is used to bootstrap and interact with Flux.

To install the CLI with Homebrew run:
```bash
brew install fluxcd/tap/flux
```

<div style="border-left: 4px solid #00b894; background-color: #e8fdf5; padding: 0.75em 1em; border-radius: 4px; color: #1a1a1a;">
<strong>💡 Tip:</strong> Tip: install bash completion if not installed. 
</div>
<br>

```bash
brew install bash-completion
```

Check if installed for Flux:
```bash
brew list bash-completion
```

### Flux Bootstrap 
Reference: https://fluxcd.io/flux/installation/bootstrap/github/#github-deploy-keys

1. Create a fine grained token in Github.
2. Export the token as an environment variable:
```bash
export GITHUB_TOKEN=<gh-token>
```
3. Run the bootstrap command:
<br>
<div style="border-left: 4px solid #1e90ff; background-color: #eaf4ff; padding: 0.75em 1em; border-radius: 4px; color: #1a1a1a;">
<strong>ℹ️ Info:</strong> Before you run the bootstrap command, make sure to set your kubectl context to the correct cluster. 
</div>
<br>


```bash
flux bootstrap github \
  --token-auth \
  --owner=my-github-username \
  --repository=my-repository-name \
  --branch=main \
  --path=clusters/my-cluster \
  ```