# Node Location Metrics (Prometheus → Grafana Geomap)

## What

This folder deploys a tiny, static Prometheus metrics endpoint that publishes **region → latitude/longitude** mappings. These custom metrics are used to render a **Geomap** panel in Grafana that visualizes where the Kubernetes cluster is running (multi-region / multi-provider).

It complements the dynamic Kubernetes metadata exported by kube-state-metrics (e.g. `kube_node_labels` with `topology.kubernetes.io/region` / `zone`) by providing the missing piece: **coordinates**.

## Why

* Kubernetes exposes region/zone labels (e.g. `fsn1`, `hel1`, `nl-ams`) but **does not provide geocoordinates**.
* Grafana Geomap requires `lat/lon` fields to place markers.
* Storing a small static mapping (region → lat/lon) in Git keeps the setup:

  * deterministic,
  * auditable,
  * GitOps-friendly,
  * low-maintenance.

## How it works

### Components

* **ConfigMap**: contains a `metrics.prom` file in Prometheus text exposition format.
* **Deployment (nginx)**: serves `metrics.prom` at `GET /metrics`.
* **Service**: exposes the nginx pod on a stable ClusterIP/port.
* **ServiceMonitor**: instructs Prometheus Operator (kube-prometheus-stack) to scrape the Service endpoint.

### Metrics exposed

Two gauge metrics are published (one series per region mapping):

* `k8s_region_lat{provider="...",region="...",city="...",zone="..."} <latitude>`
* `k8s_region_lon{provider="...",region="...",city="...",zone="..."} <longitude>`

Example:

```
k8s_region_lat{provider="hetzner",region="hel1",city="Helsinki"} 60.169520
k8s_region_lon{provider="hetzner",region="hel1",city="Helsinki"} 24.935450
```

> Note: These are **static** lookup metrics. “Dynamic” data (node counts per region, etc.) comes from kube-state-metrics and is joined in Grafana.

## Prerequisites

* kube-prometheus-stack (Prometheus Operator) installed and scraping ServiceMonitors.
* kube-state-metrics configured to export node region/zone labels (used for dynamic node counts / joins).

If you’re using kube-prometheus-stack, ensure these node labels are allowlisted:

```yaml
kube-state-metrics:
  metricLabelsAllowlist:
    - nodes=[topology.kubernetes.io/region,topology.kubernetes.io/zone]
```

This enables:

* `label_topology_kubernetes_io_region`
* `label_topology_kubernetes_io_zone`

in `kube_node_labels`.

## Deploy

This folder contains Kubernetes manifests (ConfigMap, Deployment, Service, ServiceMonitor). Apply via Flux (preferred) or kubectl.

### GitOps (Flux)

Add this folder to the relevant kustomization overlay so it’s reconciled into the cluster.

Typical validation:

```bash
kubectl -n observability get deploy,svc,servicemonitor | grep node-location
```

### Manual (debug)

```bash
kubectl -n observability apply -f .
```

## Validate

### 1) Check the endpoint serves the metrics

```bash
kubectl -n observability port-forward svc/node-location-metrics 8081:8080
curl -s http://localhost:8081/metrics | grep -E '^k8s_region_(lat|lon)'
```

### 2) Check Prometheus is scraping the metrics

In Prometheus, query:

```promql
k8s_region_lat
```

You should see one series per mapped region.

### 3) Check node region labels are available (dynamic input)

```promql
kube_node_labels{label_topology_kubernetes_io_region!=""}
```

Here’s an updated version of that section with the **exact Grafana steps** that are required to make the join work (the crucial bit is converting labels → fields first).


Here is the updated section including the **Photos layer** so provider logos can be rendered on the map.

---

## Using in Grafana (Geomap with region coordinates + provider logos)

Grafana Geomap requires actual **`lat` / `lon` fields**.
Prometheus exposes `region`, `provider`, `city` as **labels**, which must first be converted into **fields (columns)** before data can be joined.

To render **provider logos** on the map, the latitude/longitude queries add a `logo_url` label via PromQL.

---

### Queries (set all to **Instant**)

Add three Prometheus queries to the panel.

#### **A — Region latitude + logo**

```promql
label_replace(
  k8s_region_lat{provider="hetzner"},
  "logo_url",
  "https://upload.wikimedia.org/wikipedia/commons/0/0c/Hetzner_Logo.svg",
  "provider",
  ".*"
)
OR
label_replace(
  k8s_region_lat{provider="scaleway"},
  "logo_url",
  "https://upload.wikimedia.org/wikipedia/commons/3/3b/Scaleway_logo.png",
  "provider",
  ".*"
)
```

#### **B — Region longitude + logo**

```promql
label_replace(
  k8s_region_lon{provider="hetzner"},
  "logo_url",
  "https://upload.wikimedia.org/wikipedia/commons/0/0c/Hetzner_Logo.svg",
  "provider",
  ".*"
)
OR
label_replace(
  k8s_region_lon{provider="scaleway"},
  "logo_url",
  "https://upload.wikimedia.org/wikipedia/commons/3/3b/Scaleway_logo.png",
  "provider",
  ".*"
)
```

#### **C — Node count per region (rename label to `region`)**

```promql
label_replace(
  count by (label_topology_kubernetes_io_region) (
    kube_node_labels{label_topology_kubernetes_io_region!=""}
  ),
  "region", "$1",
  "label_topology_kubernetes_io_region", "(.*)"
)
```

> This ensures all queries expose a common `region="..."` label and include `provider`, `city`, and `logo_url`.


### Transformations (order matters)

1. **Labels to fields**

   * Converts Prometheus labels (`region`, `provider`, `city`, `logo_url`) into columns.
   * Without this step, **Join by field will not work**.

2. **Join by field**

   * Mode: `OUTER`
   * Field: `region`

3. **Organize fields** (recommended)

   * Rename value fields:

     * `k8s_region_lat` → `lat`
     * `k8s_region_lon` → `lon`
     * node count value → `node_count`
   * Keep: `region`, `provider`, `city`, `logo_url`, `lat`, `lon`, `node_count`


### Geomap configuration

#### Base layer (optional)

* Visualization: **Geomap**
* Location mode: **Latitude/Longitude fields**

  * Latitude field: `lat`
  * Longitude field: `lon`

#### Photos layer (provider logos)

Add a **Photos layer** on top of the map:

* Image source field: `logo_url`
* Latitude field: `lat`
* Longitude field: `lon`
* Adjust image size for readability
* Tooltip fields: `provider`, `city`, `region`, `node_count`

This renders one provider logo per region, visually proving **multi-provider, multi-region** deployment.

You can remove standard markers entirely and rely only on the Photos layer for a cleaner, diagram-like result.


## Extending the mapping

Add new regions/providers by appending entries to `metrics.prom` in the ConfigMap.

### Coverage check (optional, recommended)

This PromQL highlights regions that **have nodes** but **do not exist** in the mapping:

```promql
label_replace(
  count by (label_topology_kubernetes_io_region) (
    kube_node_labels{label_topology_kubernetes_io_region!=""}
  ),
  "region", "$1",
  "label_topology_kubernetes_io_region", "(.*)"
)
unless
count by (region) (k8s_region_lat)
```

If this returns anything, add that `region` to `metrics.prom`.

## Notes / pitfalls

* **Keep labels stable**: The `region` label in `k8s_region_lat/lon` must match the values from node labels (`topology.kubernetes.io/region`) exactly.
* **Prometheus Operator selection**: If your Prometheus instance uses ServiceMonitor selectors, ensure the ServiceMonitor labels match (commonly `release: kube-prometheus-stack`).
* **Don’t overdo per-node coordinates**: Nodes churn and overlap. Region-based markers are simpler, stable, and read well for “multi-provider / multi-region” visuals.
