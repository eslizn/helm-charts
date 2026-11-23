#!/usr/bin/env bash
# DeepSeek Harness container entrypoint.
#
# dsh refuses a wildcard --host, so the process binds one concrete address.
# The chart passes the Pod IP through the downward API and Service/Ingress
# traffic reaches dsh directly. kubectl port-forward is different: the kubelet
# dials localhost inside the Pod's network namespace, so a tiny loopback TCP
# proxy forwards 127.0.0.1:<port> to the Pod IP. That is the only reason the
# proxy exists; probes and Ingress never use it.
#
# The image runs as the non-root dsh user (uid 10001). A PVC mounted at
# DSH_HOME, the workspace, or the shared agents root must be writable by that
# user; podSecurityContext.fsGroup (the chart defaults it to 10001) is what
# normally arranges that.
set -euo pipefail

: "${DSH_HOME:=/home/dsh/.dsh}"
: "${DSH_WORKSPACE:=/workspace}"
: "${DSH_AGENTS_HOME:=/home/dsh/.agents}"
: "${DSH_WEB_PORT:=3080}"
export DSH_HOME DSH_WORKSPACE DSH_AGENTS_HOME DSH_WEB_PORT

if ! [[ "$DSH_WEB_PORT" =~ ^[0-9]+$ ]]; then
  echo "dsh-entrypoint: DSH_WEB_PORT must be a number, got '$DSH_WEB_PORT'" >&2
  exit 1
fi

ensure_writable_dir() {
  local name="$1" path="$2"
  if [[ ! -d "$path" ]]; then
    if ! mkdir -p "$path"; then
      echo "dsh-entrypoint: cannot create $name $path" >&2
      exit 1
    fi
  fi
  if [[ ! -w "$path" ]]; then
    echo "dsh-entrypoint: $name $path is not writable by uid $(id -u)." >&2
    echo "dsh-entrypoint: with a PVC, set podSecurityContext.fsGroup to the container gid ($(id -g))." >&2
    exit 1
  fi
}

ensure_writable_dir "DSH_HOME" "$DSH_HOME"
ensure_writable_dir "workspace" "$DSH_WORKSPACE"
ensure_writable_dir "agents home" "$DSH_AGENTS_HOME"

bind_host="${POD_IP:-}"
if [[ -z "$bind_host" ]]; then
  bind_host="$(hostname -i 2>/dev/null | awk '{print $1}' || true)"
fi
if [[ -z "$bind_host" ]]; then
  echo "dsh-entrypoint: cannot determine a bind address; set POD_IP or run with a network interface." >&2
  exit 1
fi
export POD_IP="$bind_host"

if [[ "$bind_host" != "127.0.0.1" && "$bind_host" != "::1" ]]; then
  node /usr/local/bin/dsh-portproxy.mjs &
  proxy_pid=$!
  # A bind failure exits the proxy immediately; surface that before dsh starts
  # instead of leaving port-forward silently broken.
  sleep 0.2
  if ! kill -0 "$proxy_pid" 2>/dev/null; then
    echo "dsh-entrypoint: dsh-portproxy failed to start" >&2
    exit 1
  fi
fi

args=(--profile web --no-open --host "$bind_host" --port "$DSH_WEB_PORT")
if [[ -n "${DSH_PUBLIC_URL:-}" ]]; then
  args+=(--public-url "$DSH_PUBLIC_URL")
fi
if [[ -n "${DSH_TRUSTED_HOSTS:-}" ]]; then
  IFS=',' read -r -a trusted_hosts <<< "$DSH_TRUSTED_HOSTS"
  for authority in "${trusted_hosts[@]}"; do
    if [[ -n "$authority" ]]; then
      args+=(--trusted-host "$authority")
    fi
  done
fi

cd "$DSH_WORKSPACE"
exec dsh "${args[@]}" "$@"
