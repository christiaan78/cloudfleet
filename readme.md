# Cloud-Agnostic Platform

A personal, evolving platform-engineering project focused on building an automated, secure, and cloud-agnostic application platform using GitOps.  
This repository contains the full infrastructure, Kubernetes manifests, Terraform modules, documentation, and tooling that power the platform.

---

## ✨ Goals

- Build a real-world multi-cloud platform (Hetzner, Scaleway, local clusters)
- Use GitOps (Flux) as the control plane for all Kubernetes workloads
- Standardize infrastructure using Terraform and reusable modules
- Deploy production-style services (Vault, Traefik, Prometheus stack, etc.)
- Practice secure secret management using SOPS and Vault
- Host real applications, including Nextcloud and internal developer tooling
- Showcase platform engineering capabilities in a long-term, public repository

---

## 🧩 Architecture Overview

High-level components:
- **Infrastructure:** Terraform modules for cloud providers and networking  
- **Compute:** Kubernetes clusters provisioned with Cloudfleet  
- **GitOps:** FluxCD controlling all YAML/Helm-based deployments  
- **Networking:** Traefik ingress, internal/external DNS  
- **Security:** Vault, SOPS, age, mTLS, Cloudflare  
- **Observability:** Prometheus, Alertmanager, Grafana  
- **Applications:** Podinfo, Nextcloud (planned), internal tools, AI workloads (planned)

➡️ Detailed architecture diagrams can be found in `/docs/architecture.md`.

---

## 📁 Repository Structure

```

clusters/          # Kubernetes clusters: dev, prod, multi-cloud
infrastructure/    # Terraform modules and cloud provisioning
kubernetes/        # Apps, core components, and platform services
pipelines/         # CI/CD examples (GitHub Actions, GitLab)
docs/              # Documentation, PoC notes, architecture, roadmap
scripts/           # Utility scripts

```

---

## 🚀 Deployed Applications (Current)

- Prometheus Stack  
- Traefik  
- Vault (internal DNS, TLS)  
- Podinfo (demo app)

📌 Upcoming deployments are tracked in the project roadmap.

---

## 🔐 Secret Management

This repository uses:
- **SOPS + age** for GitOps-safe secret encryption  
- **HashiCorp Vault** for runtime secrets and platform services  
- **Terraform Vault provider** (planned) for dynamic secret generation  

More info: `/docs/secrets.md`

---

## 🔄 GitOps Workflow

This platform is fully managed by **Flux**, including:
- HelmReleases  
- Kustomizations  
- Alerts and health checks  
- Automated rollouts  
- Image update automation (future)

Documentation: `/docs/gitops.md`

---

## 🌍 Environments

```

clusters/
development/
staging/ (planned)
production/

```

Each environment has its own:
- Base infra
- Apps
- Secrets
- Policies (OPA/Gatekeeper planned)

---

## 🗺️ Roadmap

The project is a continuous, long-term platform-engineering effort.  
See `docs/roadmap.md` for the full, detailed plan.

High-level next steps:
- Deploy Nextcloud using GitOps
- Expand Terraform modules (DNS, firewall, cloud infra)
- Add CI pipelines for validation and automation
- Deploy Plane or OpenProject for project planning
- Add AI inference workloads (GPU when available)
- Integrate cost monitoring (Kubecost or OpenCost)
- Implement Vault auto-unseal with cloud KMS

---

## 🧱 Technologies Used

- Kubernetes  
- FluxCD  
- Terraform  
- Traefik  
- Vault  
- SOPS / age  
- Prometheus stack  
- Cloudfleet  
- GitHub Actions  

---

## 🤝 Contributions

This is a personal platform engineering project, but feedback, ideas, and suggestions are always welcome.

```
