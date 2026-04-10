FROM debian:bookworm-slim

# ── system packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        python3 \
        python3-flask \
        python3-flask-cors \
        curl \
        ca-certificates \
        qemu-user-static \
        file \
        netcat-traditional \
        net-tools \
    && rm -rf /var/lib/apt/lists/*

# ── ttyd (web terminal) ───────────────────────────────────────────────────────
# Pre-built static binary; swap the URL for arm64 if needed.
RUN TTYD_VER=1.7.7 && \
    ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
        amd64)   TTYD_BIN=ttyd.x86_64  ;; \
        arm64)   TTYD_BIN=ttyd.aarch64 ;; \
        *)       TTYD_BIN=ttyd.x86_64  ;; \
    esac && \
    curl -fsSL \
        "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VER}/${TTYD_BIN}" \
        -o /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd

# ── HTTP Basic Auth credentials ──────────────────────────────────────────────
# Generates /etc/nginx/htpasswd with admin:admin at build time.
RUN echo "admin:$(openssl passwd -apr1 admin)" > /etc/nginx/htpasswd

# ── firmware rootfs mount-point ───────────────────────────────────────────────
RUN mkdir -p /firmware

# ── nginx config ──────────────────────────────────────────────────────────────
COPY nginx.conf /etc/nginx/nginx.conf

# ── application files ─────────────────────────────────────────────────────────
COPY mock-controller/ /app/mock-controller/
COPY uart-sim/        /app/uart-sim/
COPY www/             /app/www/
COPY entrypoint.sh    /entrypoint.sh
RUN chmod +x /entrypoint.sh /app/uart-sim/uart-session.sh /app/uart-sim/uart-inner.sh /app/uart-sim/attacker-shell.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
