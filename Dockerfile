# syntax=docker/dockerfile:1
# ==============================================================================
# BERMUDA x AETHER Core Gateway - All-in-One Self-Contained Container
# Architecture: Multi-Stage Hybrid (Xray-core + Aether MASQUE Core + Caddy Ingress)
# Target Environment: Railway Cloud PaaS / GitHub Automated CI/CD
# ==============================================================================

# ------------------------------------------------------------------------------
# STAGE 1: Artifact Fetcher & Validation Engine
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim AS builder

ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/build

RUN set -eux; \
    ARCH="${TARGETARCH:-amd64}"; \
    case "${ARCH}" in \
        "amd64"|"x86_64") XRAY_ARCH="64"; AETHER_ARCH="x86_64" ;; \
        "arm64"|"aarch64") XRAY_ARCH="arm64-v8a"; AETHER_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac; \
    echo "Downloading Xray-core for ${XRAY_ARCH}..."; \
    curl -fsSL "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o xray.zip; \
    unzip -q xray.zip -d /tmp/xray; \
    install -m 755 /tmp/xray/xray /usr/local/bin/xray; \
    mkdir -p /usr/local/share/xray; \
    cp /tmp/xray/geoip.dat /usr/local/share/xray/geoip.dat; \
    cp /tmp/xray/geosite.dat /usr/local/share/xray/geosite.dat; \
    \
    echo "Downloading Aether Core for ${AETHER_ARCH}..."; \
    curl -fsSL "https://github.com/CluvexStudio/Aether/releases/latest/download/aether-linux-${AETHER_ARCH}.tar.gz" -o aether.tar.gz; \
    tar -xzf aether.tar.gz -C /tmp; \
    install -m 755 /tmp/aether /usr/local/bin/aether; \
    \
    /usr/local/bin/xray version; \
    /usr/local/bin/aether --version || true

# ------------------------------------------------------------------------------
# STAGE 2: Caddy Ingress Source Extraction
# ------------------------------------------------------------------------------
FROM caddy:2-alpine AS caddy-source

# ------------------------------------------------------------------------------
# STAGE 3: Final Hardened Runtime Environment
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim

LABEL maintainer="BERMUDA Institutional Core" \
      description="Zero-Defect VLESS/Trojan to WARP MASQUE Chained Outbound Engine" \
      version="10.0-production"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    XRAY_LOCATION_ASSET=/usr/local/share/xray \
    AETHER_CONFIG=/data/aether.toml

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    procps \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/xray /usr/local/bin/xray
COPY --from=builder /usr/local/share/xray /usr/local/share/xray
COPY --from=builder /usr/local/bin/aether /usr/local/bin/aether
COPY --from=caddy-source /usr/bin/caddy /usr/local/bin/caddy

RUN mkdir -p /etc/xray /data /var/www/html /var/log/gateway /etc/caddy \
    && chmod -R 777 /data

# ایجاد صفحه وب استاتیک قانونی (Decoy Anti-Probing Asset)
RUN printf '%s\n' \
'<!DOCTYPE html>' \
'<html lang="en">' \
'<head>' \
'    <meta charset="UTF-8">' \
'    <meta name="viewport" content="width=device-width, initial-scale=1.0">' \
'    <title>Edge Node Gateway</title>' \
'    <style>' \
'        body { background:#0a0a0a; color:#737373; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; display:flex; align-items:center; justify-content:center; height:100vh; margin:0; }' \
'        .box { border:1px solid #262626; padding:24px 32px; border-radius:8px; background:#111111; }' \
'        .status { color:#10b981; font-weight:bold; }' \
'    </style>' \
'</head>' \
'<body>' \
'    <div class="box">' \
'        <p><span class="status">●</span> CLOUD_INGRESS_ACTIVE</p>' \
'        <p style="font-size:12px; margin-bottom:0;">Service Health: Nominal · 200 OK</p>' \
'    </div>' \
'</body>' \
'</html>' > /var/www/html/index.html

# ساخت مستقیم و درونی اسکریپت راه‌انداز (Self-Contained Orchestrator)
RUN cat <<'EOF' > /entrypoint.sh
#!/usr/bin/env bash
set -u

export PORT="${PORT:-8080}"
export AETHER_BIND="${AETHER_BIND:-127.0.0.1:1819}"
export AETHER_CONFIG="${AETHER_CONFIG:-/data/aether.toml}"
export AETHER_SCAN="${AETHER_SCAN:-balanced}"
export AETHER_PROTOCOL="${AETHER_PROTOCOL:-masque}"

CADDY_PID=""
XRAY_PID=""
AETHER_PID=""

echo "================================================================================"
echo "   BERMUDA MASTER KEY x AETHER CLUSTER GATEWAY"
echo "   Architecture : Chained Outbound (VLESS/Trojan -> WARP MASQUE)"
echo "   Ingress Port : :${PORT} (Dynamic Railway Binding)"
echo "   Egress Core  : Aether MASQUE over HTTP/3 / HTTP/2"
echo "================================================================================"

cleanup() {
    local exit_code="${1:-0}"
    echo ""
    echo "[ORCHESTRATOR] Intercepted termination signal. Initiating graceful shutdown..."
    trap - SIGTERM SIGINT SIGHUP EXIT

    if [ -n "$CADDY_PID" ] && kill -0 "$CADDY_PID" 2>/dev/null; then
        echo "[ORCHESTRATOR] Stopping Caddy Ingress (PID: $CADDY_PID)..."
        kill -TERM "$CADDY_PID" 2>/dev/null || true
    fi

    if [ -n "$XRAY_PID" ] && kill -0 "$XRAY_PID" 2>/dev/null; then
        echo "[ORCHESTRATOR] Stopping Xray Core (PID: $XRAY_PID)..."
        kill -TERM "$XRAY_PID" 2>/dev/null || true
    fi

    if [ -n "$AETHER_PID" ] && kill -0 "$AETHER_PID" 2>/dev/null; then
        echo "[ORCHESTRATOR] Stopping Aether MASQUE Daemon (PID: $AETHER_PID)..."
        kill -TERM "$AETHER_PID" 2>/dev/null || true
    fi

    wait "$CADDY_PID" 2>/dev/null || true
    wait "$XRAY_PID" 2>/dev/null || true
    wait "$AETHER_PID" 2>/dev/null || true

    echo "[ORCHESTRATOR] All child processes safely reaped. Gateway stopped cleanly."
    exit "$exit_code"
}

trap 'cleanup 143' SIGTERM
trap 'cleanup 130' SIGINT
trap 'cleanup 129' SIGHUP

mkdir -p /etc/caddy /data /var/log/gateway

# مکانیزم خودترمیمی برای تضمین عدم تداخل پورت‌ها
if [ -f /etc/xray/config.json ]; then
    sed -i 's/"port": 8080/"port": 10001/g' /etc/xray/config.json 2>/dev/null || true
    sed -i 's/"port": 8081/"port": 10002/g' /etc/xray/config.json 2>/dev/null || true
    sed -i 's/"port": 8082/"port": 10003/g' /etc/xray/config.json 2>/dev/null || true
    sed -i 's/"listen": "0.0.0.0"/"listen": "127.0.0.1"/g' /etc/xray/config.json 2>/dev/null || true
fi

echo "[ORCHESTRATOR] Synthesizing dynamic reverse-proxy matrix for Port :${PORT}..."
cat <<CADDYCONF > /etc/caddy/Caddyfile
{
    admin off
    auto_https off
}

:${PORT} {
    log {
        output discard
    }

    # Ingress Route 1: VLESS WebSocket Pipeline
    reverse_proxy /api/v1/live* 127.0.0.1:10001

    # Ingress Route 2: Trojan WebSocket Pipeline
    reverse_proxy /api/v1/gateway* 127.0.0.1:10002

    # Ingress Route 3: VLESS XHTTP Pipeline
    reverse_proxy /api/v1/sync* 127.0.0.1:10003

    # Decoy Masquerade Asset: Anti-Probing 200 OK Response
    root * /var/www/html
    file_server
}
CADDYCONF

echo "[ORCHESTRATOR] Spawning Aether MASQUE Core on ${AETHER_BIND}..."
/usr/local/bin/aether \
    --bind "${AETHER_BIND}" \
    --${AETHER_PROTOCOL} \
    -4 \
    --scan "${AETHER_SCAN}" \
    --config "${AETHER_CONFIG}" &
AETHER_PID=$!

echo "[ORCHESTRATOR] Aether daemon active (PID: ${AETHER_PID})."

echo "[ORCHESTRATOR] Spawning Xray Switching Core (/etc/xray/config.json)..."
/usr/local/bin/xray run -config /etc/xray/config.json &
XRAY_PID=$!

echo "[ORCHESTRATOR] Xray core active (PID: ${XRAY_PID})."

echo "[ORCHESTRATOR] Spawning Caddy Edge Ingress Gateway on Port :${PORT}..."
/usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
CADDY_PID=$!

echo "[ORCHESTRATOR] Caddy ingress active (PID: ${CADDY_PID}). Edge router listening."

echo "[ORCHESTRATOR] Performing non-blocking data-plane probe on ${AETHER_BIND}..."
(
    READY=0
    for i in $(seq 1 20); do
        if bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/1819" 2>/dev/null; then
            echo "[HEALTHCHECK] Cloudflare WARP MASQUE Egress Verified (127.0.0.1:1819 is active)."
            READY=1
            break
        fi
        sleep 1
    done
    if [ "$READY" -eq 0 ]; then
        echo "[HEALTHCHECK] WARP initialization taking longer than usual; scanner running in background."
    fi
) &

echo "[ORCHESTRATOR] Cluster Gateway online and operational. Monitoring process health..."

SUPERVISOR_STATUS=0
wait -n "$CADDY_PID" "$XRAY_PID" "$AETHER_PID" || SUPERVISOR_STATUS=$?

echo "[ORCHESTRATOR] Detected termination of core process (Exit Status: ${SUPERVISOR_STATUS})."
cleanup "${SUPERVISOR_STATUS}"
EOF

RUN chmod +x /entrypoint.sh

# کپی تنظیمات سوییچینگ Xray (فاز ۱)
COPY config.json /etc/xray/config.json

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
