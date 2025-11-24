# Cloud-Agnostic Platform

A personal, evolving platform-engineering project focused on building an automated, secure, and cloud-agnostic application platform using GitOps.  
This repository contains the full infrastructure, Kubernetes manifests and tooling that power the platform.

---

## Goals

- Build a real-world multi-cloud platform (Hetzner, Scaleway)
- Use GitOps (Flux) as the control plane for all Kubernetes workloads
- Standardize infrastructure using Terraform and reusable modules (future)
- Deploy production-style services (Vault, Traefik, Prometheus stack, etc.)
- Practice secure secret management using SOPS and Vault
- Host real applications, including Nextcloud and internal developer tooling
- Showcase platform engineering capabilities in a long-term, public repository

---

## Architecture Overview

High-level components:  
- **Compute:** Kubernetes clusters provisioned with Cloudfleet  
- **GitOps:** FluxCD controlling all YAML/Helm-based deployments  
- **Networking:** Traefik ingress, internal/external DNS  
- **Security:** Vault, SOPS, TLS, Cloudflare (planned) 
- **Observability:** Prometheus, Alertmanager, Grafana  
- **Applications:** Podinfo, Nextcloud (planned), internal developer tools (panned), AI workloads (planned)
- **Infrastructure:** Terraform modules for cloud providers and networking (planned), Ansible for VM provisioning and configuration management (planned)

---

## Repository Structure

```
gitops/            # Kubernetes clusters: dev, prod, multi-cloud
infrastructure/    # Terraform modules and cloud provisioning
cicd/              # CI/CD pipelines (GitHub Actions)
documentation/     # Documentation, PoC notes, architecture, roadmap
tools/             # Utility manifests, scripts

```

---

## Deployed Applications (Current)

- Prometheus Stack  
- Traefik  
- Hashicorp Vault (internal DNS, TLS)  
- Hashicorp Vault Secrets Operator
- Podinfo (demo app)
- Cert manager
- Hetzner Cloud CSI

Upcoming deployments are tracked in the project roadmap.

---

## Secret Management

This repository uses:
- **HashiCorp Vault** for runtime secrets and platform services  
- **Terraform Vault provider** (planned) for dynamic secret generation
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

## Roadmap

The project is a continuous, long-term platform-engineering effort.  
See `documentation/roadmap.md` for the full, detailed plan.

High-level next steps:
- Expand Prometheus stack with alerting and dashboards
- Setup backup and restore for Hashicorp Vault
- Deploy Nextcloud using GitOps
- Expand platform with Terraform modules and Ansible playbook (DNS, firewall, cloud infra)
- Add CI pipelines for validation and automation
- Deploy Plane or OpenProject for project planning
- Add AI workloads (on separate cloud provider)
- Integrate cost monitoring
- Implement Vault auto-unseal with cloud KMS

---

## Technologies Used

- Kubernetes  
- FluxCD  
- Terraform
- Ansible
- Traefik  
- Vault
- Prometheus stack  
- Cloudfleet  
- GitHub Actions  

---

## Contributions

This is a personal platform engineering project, but feedback, ideas, and suggestions are always welcome.

```
