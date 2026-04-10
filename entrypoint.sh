#!/bin/bash
# entrypoint.sh – starts all services inside the container
set -e

log() { echo "[entrypoint] $*"; }

# ── sanity check ───────────────────────────────────────────────────────────────
if [[ ! -f /firmware/www/index.html ]]; then
    echo "[entrypoint] ERROR: /firmware/www/index.html not found."
    echo "             Mount the firmware rootfs: -v ./ext-root:/firmware:ro"
    exit 1
fi

# ── mock controller ───────────────────────────────────────────────────────────
log "Starting mock controller (Flask) …"
python3 /app/mock-controller/app.py &

# ── ttyd (UART web terminal) ──────────────────────────────────────────────────
log "Starting ttyd on :7681 (base-path /uart) …"
ttyd \
    --port 7681 \
    --base-path /uart \
    --writable \
    /app/uart-sim/uart-session.sh &

# ── nginx ─────────────────────────────────────────────────────────────────────
log "Starting nginx …"
# Remove default site that would conflict
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

exec nginx -g "daemon off;"
