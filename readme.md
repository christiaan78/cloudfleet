# Cloudfleet Multi-Cloud Kubernetes PoC

<div style="border-left: 4px solid #1e90ff; background-color: #eaf4ff; padding: 0.75em 1em; border-radius: 4px; color: #1a1a1a;">
This Proof-of-Concept (PoC) demonstrates that a secure, production-grade Kubernetes platform can be built entirely on <strong>European cloud providers</strong> — managed declaratively through FluxCD and without reliance on US hyperscalers.
</div>

---

## Objectives

Showcase a **multi-cloud, EU-centric Kubernetes platform** that is:
- **Resilient** — able to continue operating when a provider fails  
- **Secure** — all communication and secrets encrypted, least-privilege by default  
- **Observable** — unified metrics, logs, and health across clouds  
- **Vendor-agnostic** — deployable across Cloudfleet, Hetzner, Scaleway, OVH Cloud, and StackIT  

---

## PoC Scenarios

### 1️⃣ Multi-provider cluster (Cloudfleet taints & tolerations)

Run a **single logical cluster** (development) across multiple providers using Cloudfleet’s multi-provider node pools.

**Goal:** Demonstrate unified control plane with workloads scheduled based on provider-specific taints and tolerations.

**Approach:**
- Base cluster managed by Cloudfleet
- Add node pools on **Hetzner** and **Scaleway**
- Label nodes with provider metadata (`node.cloudprovider=hetzner`)
- Use taints/tolerations and nodeSelectors for targeted scheduling
- Deploy a **provider-aware Podinfo** instance per provider  
  → *e.g., “Hello from Hetzner!”, “Hello from Scaleway!”*

**Outcome:**  
One cluster, multiple providers, all observable via Grafana dashboards and Flux GitOps sync.

---

### 2️⃣ Failover cluster (dual control planes)

Build a **second Cloudfleet cluster** (production) on a different provider to demonstrate full failover capability.

**Goal:** Show resilience when one provider or cluster becomes unavailable.

**Approach:**
- `development` cluster (primary)  
- `production` cluster (failover) on another provider (e.g., OVH Cloud)
- Both bootstrapped via Flux (`clusters/development`, `clusters/production`)
- Shared GitOps repo; environment overlays control differences
- DNS-based failover via Cloudflare or Traefik middleware
- Data-agnostic services (e.g., Podinfo) used to validate cut-over

**Outcome:**  
Automated redeployment and DNS rerouting without manual steps. Unified observability confirms continuity.

---

### 3️⃣ Shared observability layer

Implement a **unified monitoring stack** across all clusters and providers.

**Goal:** Gain a single observability view across Cloudfleet, Hetzner, Scaleway, OVH Cloud, and StackIT.

**Approach:**
- Deploy **Prometheus**, **Grafana**, **Loki**, and **Alloy**
- Use remote-write or federation to push data to a central Grafana instance (EU-hosted)
- Dashboards display node pools, provider spread, and latency
- Include **CrowdSec** for basic intrusion detection
- Visualize **failover events** and per-provider performance

**Outcome:**  
Cross-provider insights with metrics, logs, and security events visible from one Grafana dashboard.

---

## Core Pillars

| Pillar | Description | Key Tools / Components |
|:--|:--|:--|
| **1. Platform Infrastructure** | Declarative Kubernetes setup managed by Flux | Cloudfleet, Hetzner, Scaleway, OVH Cloud, StackIT |
| **2. GitOps Lifecycle** | Everything as code, automated reconciliation | FluxCD, Helm, Kustomize |
| **3. Observability** | Unified monitoring, logging, and alerting | Prometheus, Grafana, Loki, Alloy |
| **4. Security** | Built-in zero-trust posture, secret management | Hashicorp Vault, SOPS, CrowdSec, Kyverno (baseline policies), Cloudflare DNS-01 |
| **5. Applications** | Workloads used to validate architecture | Podinfo, Traefik reverse proxy |
| **6. Data Sovereignty** | EU-only providers and data residency compliance | EU regions only, Cloudflare EU zones |

---

## Implementation Plan

| Phase | Focus | Key Deliverables |
|:--|:--|:--|
| **Phase 1 – Foundation Setup** | Bootstrap Cloudfleet cluster and Flux. Establish base folder structure and cluster manifests. | ✅ Completed Flux bootstrap |
| **Phase 2 – Observability Layer** | Deploy Prometheus, Grafana, Loki, and Alloy across the cluster. | Unified metrics and logs |
| **Phase 3 – Application Layer** | Deploy Podinfo (multi-provider aware) and Traefik as reverse proxy. | Test connectivity and routing |
| **Phase 4 – Multi-provider Expansion** | Add StackIT and Scaleway node pools to the same Cloudfleet cluster. Configure taints/tolerations. | Cross-provider workload placement |
| **Phase 5 – Failover Scenario** | Create a second (production) Cloudfleet cluster on a different provider. Sync via Flux and test DNS failover. | Verified resiliency and continuity |
| **Phase 6 – Showcase & Documentation** | Capture dashboards, diagrams, and results. Prepare final write-up. | PoC summary and visuals |

---

## Security Model

<div style="border-left: 4px solid #00b894; background-color: #e8fdf5; padding: 0.75em 1em; border-radius: 4px; color: #1a1a1a;">
All secrets are managed via <strong>SOPS</strong> and encrypted before being stored in Git. No plaintext secrets are committed.
</div>

**Key practices:**
- SOPS with AGE keys for secret encryption  
- `age.agekey` stored in cluster as Kubernetes Secret (`flux-system/sops-age`)  
- Cloudflare DNS-01 for TLS (EU zones only)  
- CrowdSec and Kyverno enforce secure baseline policies  
- GitOps auditability — full change history in Git  

---

## Observability Goals

- Prometheus & Grafana dashboards show:
  - Node/provider distribution
  - Podinfo response latency per provider
  - Cross-region network performance
- Loki + Alloy provide centralized log streaming
- Alerts for:
  - Node or cluster unavailability
  - Provider imbalance or loss
  - CrowdSec detections

---

## Expected Outcomes

- **Demonstrated viability** of EU-based, multi-cloud Kubernetes  
- **Full GitOps lifecycle** with declarative configuration  
- **Resilient multi-cluster deployment** with observable failover  
- **Data sovereignty** — no dependency on US hyperscalers  

---
