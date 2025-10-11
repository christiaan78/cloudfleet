```markdown
# Port-forward helper — Traefik

Small helper to run a **single** port-forward to Traefik and reach all your internal Ingress hosts. 

## What it does
- Starts a background `kubectl port-forward` from Traefik’s Service to **localhost**.
- Defaults to mapping **18080→80** (HTTP) and **18443→443** (HTTPS).
- Lets you check status or stop the forward cleanly.

## Prereqs
- `kubectl` logged into the target cluster.
- Traefik Service exists in the expected namespace (default `ingress-traefik`).
- Your workstation’s `/etc/hosts` contains the hostnames you use (e.g. `development.vault.internal`).

Example `/etc/hosts` line (on your **workstation**):
```

127.0.0.1  development.vault.internal development.grafana.internal development.podinfo.internal

```

## Usage
- **Start**: `Tools/scripts/port-forwarding/port-forward.sh start`
- **Status**: `Tools/scripts/port-forwarding/port-forward.sh status`
- **Stop**: `Tools/scripts/port-forwarding/port-forward.sh stop`

Then browse:
- `http://<host>:18080` or `https://<host>:18443`  
  e.g. `https://development.vault.internal:18443`

## Customization (env vars)
- `NS` (default `ingress-traefik`) — Traefik namespace  
- `SVC` (default `traefik`) — Traefik Service name  
- `MAP_HTTP` (default `18080:80`) — local:remote HTTP ports  
- `MAP_HTTPS` (default `18443:443`) — local:remote HTTPS ports  
- `DEBUG=1` — run foreground, print kubectl output

Example:
```

NS=my-ingress SVC=traefik MAP_HTTP=8080:80 MAP_HTTPS=8443:443 ./port-forward.sh start

```

## Notes & tips
- If the script reports “OFF”, a local port is likely in use or the Service/namespace name is wrong. Try `DEBUG=1` to see the error.
- To use **no port in the URL** (`https://host`), forward **443→443** (and **80→80**) and ensure those ports are free; may require elevated privileges.
- This forward serves **any** app with a Traefik Ingress—just add more hostnames to `/etc/hosts` as you add routes.
```
