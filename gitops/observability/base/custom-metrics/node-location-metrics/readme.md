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


## Using in Grafana (Geomap with region coordinates)

Grafana Geomap requires actual **`lat` / `lon` fields**.
Prometheus exposes `region`, `provider`, `city` as **labels**, which must first be converted into **fields (columns)** before you can join data.

### Queries (set all to **Instant**)

Add three Prometheus queries to the panel:

**A — Region latitude**

```promql
k8s_region_lat
```

**B — Region longitude**

```promql
k8s_region_lon
```

**C — Node count per region (rename label to `region`)**

```promql
label_replace(
  count by (label_topology_kubernetes_io_region) (
    kube_node_labels{label_topology_kubernetes_io_region!=""}
  ),
  "region", "$1",
  "label_topology_kubernetes_io_region", "(.*)"
)
```

> This ensures all three queries expose a common `region="..."` label.


### Transformations (order matters)

1. **Labels to fields**

   * This converts Prometheus labels (`region`, `provider`, `city`) into actual columns.
   * Without this step, **Join by field will not work**.

2. **Join by field**

   * Mode: `OUTER`
   * Field: `region`

3. **Organize fields** (recommended)

   * Rename value fields:

     * `k8s_region_lat` → `lat`
     * `k8s_region_lon` → `lon`
     * node count value → `node_count`
   * Keep: `region`, `provider`, `city`, `lat`, `lon`, `node_count`


### Geomap configuration

* Visualization: **Geomap**
* Location mode: **Latitude/Longitude fields**

  * Latitude field: `lat`
  * Longitude field: `lon`
* Tooltip fields: `provider`, `city`, `region`, `node_count`
* Marker size: `node_count` (optional but visually useful)

This produces one marker per region, sized by the number of nodes running there.


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
