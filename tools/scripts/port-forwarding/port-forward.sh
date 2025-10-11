#!/usr/bin/env bash
# Simple manager for Traefik port-forward (no hosts editing).
# Usage:
#   tools/scripts/port-forwarding/port-forward.sh start
#   tools/scripts/port-forward-forwarding/port-forward.sh stop
#   tools/scripts/port-forwarding/port-forward.sh status
#
# Note: add hostnames to your WORKSTATION's /etc/hosts, e.g.:
#   127.0.0.1 development.vault.internal grafana.internal
#
# Then browse:
#   http://development.vault.internal:18080
#   https://development.vault.internal:18443
#
# Env vars you can override: NS, SVC, MAP_HTTP, MAP_HTTPS, DEBUG
set -euo pipefail

NS=${NS:-ingress-traefik}
SVC=${SVC:-traefik}
MAP_HTTP=${MAP_HTTP:-18080:80}
MAP_HTTPS=${MAP_HTTPS:-18443:443}
DEBUG=${DEBUG:-0}

pat_http="kubectl.*port-forward.*svc/${SVC} ${MAP_HTTP}.*-n ${NS}"
pat_https="kubectl.*port-forward.*svc/${SVC} ${MAP_HTTPS}.*-n ${NS}"

start() {
  if pgrep -f "$pat_http" >/dev/null && pgrep -f "$pat_https" >/dev/null; then
    echo "✔ Traefik port-forward already running (:${MAP_HTTP%%:*}, :${MAP_HTTPS%%:*})"
    status
    return
  fi

  echo "→ Forwarding Traefik ${NS}/${SVC} (${MAP_HTTP}, ${MAP_HTTPS})"
  if [[ "$DEBUG" == "1" ]]; then
    kubectl -n "$NS" port-forward "svc/${SVC}" "$MAP_HTTP" "$MAP_HTTPS" &
  else
    kubectl -n "$NS" port-forward "svc/${SVC}" "$MAP_HTTP" "$MAP_HTTPS" >/dev/null 2>&1 &
  fi

  pid=$!
  sleep 1
  if ! ps -p "$pid" >/dev/null 2>&1; then
    echo "⚠ port-forward exited quickly. Re-run with DEBUG=1 to see errors."
  fi
  status
  echo "Reminder: update /etc/hosts on your WORKSTATION, e.g.:"
  echo "  127.0.0.1 development.vault.internal grafana.internal"
  echo "Then browse https://<hostname>:${MAP_HTTPS%%:*}"
}

stop() {
  pkill -f "$pat_http" >/dev/null 2>&1 || true
  pkill -f "$pat_https" >/dev/null 2>&1 || true
  echo "✖ Stopped Traefik port-forward(s)"
}

status() {
  if pgrep -f "$pat_http" >/dev/null; then
    echo "RUN :${MAP_HTTP%%:*} → $NS/$SVC:${MAP_HTTP#*:}"
  else
    echo "OFF :${MAP_HTTP%%:*} → $NS/$SVC:${MAP_HTTP#*:}"
  fi
  if pgrep -f "$pat_https" >/dev/null; then
    echo "RUN :${MAP_HTTPS%%:*} → $NS/$SVC:${MAP_HTTPS#*:}"
  else
    echo "OFF :${MAP_HTTPS%%:*} → $NS/$SVC:${MAP_HTTPS#*:}"
  fi
}

usage() {
  echo "Usage:"
  echo "  $0 start     # start PF in background"
  echo "  $0 stop      # stop PFs"
  echo "  $0 status    # show PF status"
  echo
  echo "Env: NS=$NS SVC=$SVC MAP_HTTP=$MAP_HTTP MAP_HTTPS=$MAP_HTTPS DEBUG=$DEBUG"
}

cmd="${1:-start}"
case "$cmd" in
  start)  start ;;
  stop)   stop ;;
  status) status ;;
  *)      usage; exit 1 ;;
esac
