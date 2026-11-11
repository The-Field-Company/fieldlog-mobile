#!/bin/bash
set -euo pipefail

# The Android guest reaches this container's loopback via 10.0.2.2. Forward the
# FieldLog backend ports from loopback to the host machine so the app's default
# URLs (http://10.0.2.2:<port>) resolve to services running on the host.
BACKEND_HOST="${BACKEND_HOST:-host.docker.internal}"

for port in ${BACKEND_PORTS:-8000 8080 8090}; do
  echo "Forwarding 10.0.2.2:${port} -> ${BACKEND_HOST}:${port}"
  socat "tcp-listen:${port},bind=127.0.0.1,fork,reuseaddr" \
        "tcp:${BACKEND_HOST}:${port}" &
done

# Run budtmo's original entry command. The image's CMD is dropped when the
# entrypoint is overridden, so invoke run.sh explicitly via its APP_PATH env.
exec bash "${APP_PATH}/mixins/scripts/run.sh"
