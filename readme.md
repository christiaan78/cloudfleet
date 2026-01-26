# Cloud-Agnostic Platform

A personal, evolving platform-engineering project focused on building an automated, secure, and cloud-agnostic application platform using GitOps.  
This repository contains the full infrastructure, Kubernetes manifests and tooling that power the platform.

---

## Goals

- Build a real-world multi-cloud platform (Hetzner, Scaleway and others)
- Use GitOps (Flux) as the control plane for all Kubernetes workloads
- Standardize infrastructure using Terraform and reusable modules
- Deploy production-style services (Vault, Traefik, Prometheus stack, etc.)
- Host real applications, including Nextcloud and internal developer tooling
- Showcase platform engineering capabilities in a long-term, public repository

---

## Architecture Overview

High-level components:  
- **Compute:** Kubernetes clusters provisioned with Cloudfleet  
- **GitOps:** FluxCD controlling all YAML/Helm-based deployments  
- **Networking:** Tailscale (to be replaced by Headscale) ingress, internal/external DNS
- **Security:** Vault, SOPS, TLS 
- **Observability:** Prometheus, Alertmanager, Grafana  
- **Applications:** Podinfo, Nextcloud (planned), internal developer tools (planned), AI workloads (planned)
- **Infrastructure:** Terraform modules for cloud providers and networking, Ansible for VM provisioning and configuration management (planned)

---

## Repository Structure

```
gitops/            # Kubernetes clusters: dev, prod
infrastructure/    # Terraform modules and cloud provisioning
cicd/              # CI/CD pipelines (GitHub Actions)
documentation/     # Documentation, PoC notes, architecture, roadmap
tools/             # Utility manifests, scripts

```

---

## Deployed Applications (Current)

- Prometheus Stack  
- Traefik  
- Hashicorp Vault (TLS enabled)  
- Hashicorp Vault Secrets Operator
- Podinfo (demo app)
- Pi-Hole (used as demo app for showing multi-cloud provider setup)
- Tailscale (to access services securely without exposing the cluster to the internet)
- Cert manager
- Hetzner Cloud CSI

Upcoming deployments are tracked on the project [backlog](https://github.com/users/christiaan78/projects/2).

---

## Secret Management

This repository uses:
- **HashiCorp Vault** for runtime secrets and platform services  
- - **SOPS + age** for GitOps-safe secret encryption (if Vault cannot be used)

More info: `/documentation/secrets.md`

---

## GitOps Workflow

This platform is fully managed by **Flux**, including:
- HelmReleases  
- Kustomizations  
- Alerts (planned) and health checks
- Automated rollouts  
- Image update automation (future)

Documentation: `/documentation/gitops.md`

---

## Environments

```

clusters/
development/
production/ (planned)

```

Each environment has its own:
- Base infra
- Apps
- Secrets
- Policies

---

## Technologies Used

- Kubernetes  
- FluxCD  
- Terraform
- Ansible
- Traefik  
- Hashicorp Vault
- Prometheus stack  
- Cloudfleet  
- GitHub Actions  

---

## Contributions

This is a personal platform engineering project, but feedback, ideas, and suggestions are always welcome.

```
