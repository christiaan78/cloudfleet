# Tailscale Operator deployment and configuration

The Tailscale Kubernetes Operator is deployed via Flux as a `HelmRelease` using the upstream `tailscale-operator` chart with (mostly) default values (we only enable debug logging in this environment). Prior to deploying the operator, the tailnet is prepared following Tailscale’s documentation: we create the required OAuth client in the Tailscale admin console, configure the operator-specific tags/permissions there, and then store the generated `client_id` and `client_secret` securely in Vault.

In this repo we do not commit the OAuth credentials. Instead, in the `development` overlay we use HashiCorp Vault Secrets Operator (VSO) to sync the Vault secret into Kubernetes. Concretely, a `VaultAuth` in the `tailscale` namespace authenticates to Vault using the `tailscale` service account and the `vso-tailscale` role. A `VaultStaticSecret` then reads `secret/data/k8s/tailscale/operator-oauth` (KV v2 mount `secret`, path `k8s/tailscale/operator-oauth`) and materializes it as the Kubernetes Secret `tailscale/operator-oauth` containing `client_id` and `client_secret`. The Tailscale Operator chart consumes this Secret to authenticate to the tailnet and create/manage Tailscale resources (Ingresses and LoadBalancer services) on behalf of the cluster.

# Exposing Kubernetes Services to a Tailnet with Tailscale Operator

This repository documents a generic, production-oriented approach for exposing Kubernetes workloads privately to a Tailscale tailnet using the Tailscale Kubernetes Operator.

The patterns below are intended for:

* Private access to admin UIs (Grafana, dashboards, internal apps)
* Private access to TCP/UDP services (DNS, databases, game servers)
* GitOps-friendly manifests (Ingress/Service objects and minimal annotations)

## Assumptions

* You have a Kubernetes cluster with the Tailscale Kubernetes Operator installed.
* You have permissions to create `Ingress` and `Service` resources in your workload namespaces.
* Your tailnet has an access policy (ACLs/grants) that allows the access you intend.
* Your cluster networking is compatible with Tailscale’s requirements (some CNIs require specific settings; see “CNI requirements” below).

## Pattern 1: Expose an HTTP service (UI) via Tailscale Ingress

This pattern is ideal for web UIs and HTTP APIs.

### Example: expose a Service on port 80 via a Tailscale Ingress

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: my-namespace
spec:
  selector:
    app: myapp
  ports:
    - name: http
      port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: my-namespace
spec:
  ingressClassName: tailscale
  defaultBackend:
    service:
      name: myapp
      port:
        number: 80
```

Notes:

* Use `defaultBackend` for the simplest and most compatible configuration.
* The operator will create a Tailscale endpoint for this Ingress and advertise it in the tailnet.
* Access is typically via `https://<generated-name>.tailnet-identifier.ts.net`.

### Optional: NetworkPolicy to allow traffic from the Tailscale namespace

If your cluster enforces NetworkPolicies, allow ingress from the namespace where the operator’s proxy pods run (commonly `tailscale`):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-tailscale-to-myapp
  namespace: my-namespace
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: tailscale
      ports:
        - protocol: TCP
          port: 80
```

## Pattern 2: Expose a TCP/UDP service via a Tailscale LoadBalancer Service

This pattern is required for non-HTTP protocols such as DNS (53), SSH (22), SMTP (25), databases, or custom TCP/UDP workloads.

### Example: expose DNS on port 53 (TCP + UDP)

1. Create an internal (ClusterIP) Service for in-cluster access and health checks (recommended).
2. Create a dedicated Tailscale LoadBalancer Service to publish port 53 to the tailnet.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mydns
  namespace: my-namespace
spec:
  type: ClusterIP
  selector:
    app: mydns
  ports:
    - name: dns-udp
      protocol: UDP
      port: 53
      targetPort: 53
    - name: dns-tcp
      protocol: TCP
      port: 53
      targetPort: 53
---
apiVersion: v1
kind: Service
metadata:
  name: mydns-ts
  namespace: my-namespace
  annotations:
    tailscale.com/hostname: "mydns"
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
  allocateLoadBalancerNodePorts: false
  selector:
    app: mydns
  ports:
    - name: dns-udp
      protocol: UDP
      port: 53
      targetPort: 53
    - name: dns-tcp
      protocol: TCP
      port: 53
      targetPort: 53
```

Notes:

* Use `tailscale.com/hostname` to control the advertised name.
* Prefer `allocateLoadBalancerNodePorts: false` to avoid allocating NodePorts that you do not need.
* For DNS, expose both UDP and TCP.

### NetworkPolicy considerations for L4 services

If you use NetworkPolicies, you must allow inbound traffic to your pods from the `tailscale` namespace on the relevant ports:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-tailscale-to-mydns
  namespace: my-namespace
spec:
  podSelector:
    matchLabels:
      app: mydns
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: tailscale
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

## Validation and Troubleshooting

### Confirm the operator created the endpoint

For Ingress:

```bash
kubectl -n <namespace> describe ingress <name>
```

For LoadBalancer Service:

```bash
kubectl -n <namespace> get svc <service-name> -o yaml
```

Look for:

* `status.loadBalancer.ingress` containing a tailnet hostname and/or a `100.x.y.z` address.
* A condition such as `TailscaleProxyReady: True`.

### Verify backend health inside the cluster

Always validate the backend before debugging Tailscale:

```bash
kubectl -n <namespace> run -it --rm dns-test --image=alpine:3.20 -- sh -lc '
apk add --no-cache bind-tools >/dev/null
dig @<service>.<namespace>.svc.cluster.local google.com +time=2 +tries=1
dig +tcp @<service>.<namespace>.svc.cluster.local google.com +time=2 +tries=1
'
```

### Verify from a tailnet device

HTTP:

* Open the `https://...ts.net` hostname created by the Ingress.

TCP/UDP:

```bash
dig @<tailscale-vip-or-hostname> google.com
dig +tcp @<tailscale-vip-or-hostname> google.com
```

### Common causes

* NetworkPolicies do not allow traffic from the `tailscale` namespace to the target pods.
* Service ports do not match the target container ports.
* Hostname-based Ingress rules are not supported by the operator configuration in use; prefer `defaultBackend`.
* Cluster networking (CNI) requires specific settings to support Tailscale LoadBalancer Services.

## CNI requirements and kube-proxy replacement notes

Some CNIs (notably Cilium with kube-proxy replacement) require specific configuration for Tailscale LoadBalancer Services to function correctly, especially for TCP/UDP forwarding.

If TCP/UDP services time out on the tailnet VIP while the in-cluster Service works, check your CNI settings and consult your platform provider’s guidance. In managed clusters, you may need the provider to apply the required CNI configuration.

To confirm that the issue is related to Cilium’s kube-proxy replacement, you can run the following commands:

```bash
# Check if kube-proxy replacement is enabled
kubectl -n kube-system get configmap cilium-config -o yaml | grep kube-proxy-replacement

# Inspect Cilium status for proxy replacement mode
kubectl -n kube-system exec -it ds/cilium -- cilium status | grep "KubeProxyReplacement"

# Verify that LoadBalancer service handling is active
kubectl -n kube-system exec -it ds/cilium -- cilium service list

# Check for dropped packets or forwarding issues
kubectl -n kube-system exec -it ds/cilium -- cilium monitor --type drop
```

If `kube-proxy-replacement` is set to `strict` or `true`, and you observe that LoadBalancer traffic is not being forwarded correctly, this indicates that Cilium’s configuration must be adjusted to support Tailscale LoadBalancer Services.

## Tailscale ACL best practices

These guidelines help ensure you expose only what you intend to expose.

1. Use least privilege

* Prefer allowing access to specific services/ports rather than broad `*:*` rules.
* Start with the minimal set: specific source identities and specific destinations.

2. Use groups for humans, tags for infra

* Put users into stable groups such as `group:admins`, `group:ops`, `group:devs`.
* Tag devices/services consistently, for example:

  * `tag:k8s` for cluster workloads
  * `tag:infra` for shared infrastructure services
  * `tag:dns` for DNS endpoints

3. Scope by port and protocol

* For DNS: allow `udp:53` and `tcp:53` only.
* For web UIs: allow `tcp:443` (and `tcp:80` only if you explicitly need HTTP).

4. Prefer explicit service destinations where possible

* If you use Tailscale “Services” (LoadBalancer endpoints), scope rules to the specific service, e.g. `svc:mydns`.
* If you expose individual devices/endpoints, scope to the tag/device and port.

5. Test policy changes

* Use policy tests (if available in your workflow) and validate with `dig`, `curl`, or application-specific probes.
* When troubleshooting, temporarily broaden rules only long enough to isolate whether the issue is policy vs. networking, then revert.

### Example policy snippets (illustrative)

Allow a DNS group to use the DNS service only:

```json
{
  "grants": [
    {
      "src": ["group:DNS"],
      "dst": ["svc:mydns"],
      "ip": ["udp:53", "tcp:53"]
    }
  ]
}
```

Allow ops to access Kubernetes UIs (HTTPS only):

```json
{
  "grants": [
    {
      "src": ["group:ops"],
      "dst": ["tag:k8s"],
      "ip": ["tcp:443"]
    }
  ]
}
```

## Recommended repository layout

* `apps/<app>/` for manifests (Deployment/Service/Ingress/NetworkPolicy)
* `apps/<app>/README.md` for app-specific exposure details (ports, hostnames, validation commands)
* `docs/tailscale/` for shared Tailnet exposure patterns, ACL guidance, and troubleshooting
