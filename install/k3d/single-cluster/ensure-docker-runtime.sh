#!/usr/bin/env bash
set -euo pipefail

# Keep Docker Desktop available after macOS restarts while bounding the VM at
# 16 GiB. Docker Desktop's local backend API applies the setting and restarts
# its VM when necessary; the OpenChoreo data lives in the existing k3d volume.
SOCKET="${HOME}/Library/Containers/com.docker.docker/Data/backend.sock"
[[ -S "$SOCKET" ]] || { echo "Docker Desktop backend socket not found: $SOCKET" >&2; exit 1; }

printf '%s' '{"autoStart":true,"memoryMiB":16384}' \
  | curl --fail-with-body --silent --show-error \
      --unix-socket "$SOCKET" \
      -X POST -H 'Content-Type: application/json' \
      --data-binary @- \
      http://localhost/app/settings

if docker info >/dev/null 2>&1; then
  docker ps --filter name=k3d-openchoreo --format '{{.Names}}' \
    | while read -r container; do
        [[ -n "$container" ]] && docker update --restart unless-stopped "$container" >/dev/null
      done
fi

echo "Docker Desktop is configured for AutoStart and 16384 MiB maximum VM memory."
