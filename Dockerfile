# syntax=docker/dockerfile:1
# ==============================================================================
# BERMUDA x AETHER Core Gateway - Hardened Production Container (Netstack Boost)
# Architecture: Multi-Stage Hybrid (Xray-core + Aether MASQUE Core + Caddy Ingress)
# Base System: Ubuntu 24.04 LTS (Native GLIBC 2.39 Engine)
# Optimization: TCP Netstack 2MB Flow-Control Buffers
# ==============================================================================

FROM ubuntu:24.04 AS builder

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

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
    curl -fsSL "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o xray.zip; \
    unzip -q xray.zip -d /tmp/xray; \
    install -m 755 /tmp/xray/xray /usr/local/bin/xray; \
    mkdir -p /usr/local/share/xray; \
    cp /tmp/xray/geoip.dat /usr/local/share/xray/geoip.dat; \
    cp /tmp/xray/geosite.dat /usr/local/share/xray/geosite.dat; \
    \
    curl -fsSL "https://github.com/CluvexStudio/Aether/releases/latest/download/aether-linux-${AETHER_ARCH}.tar.gz" -o aether.tar.gz; \
    tar -xzf aether.tar.gz -C /tmp; \
    install -m 755 /tmp/aether /usr/local/bin/aether

FROM caddy:2-alpine AS caddy-source

FROM ubuntu:24.04

LABEL maintainer="BERMUDA Institutional Core" \
      description="Zero-Defect VLESS/Trojan to WARP MASQUE Chained Outbound Engine" \
      version="10.1-boosted"

# تنظیم بافرهای 2MB لایه TCP Netstack و پیش‌فرض‌های محیطی
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    XRAY_LOCATION_ASSET=/usr/local/share/xray \
    AETHER_CONFIG=/data/aether.toml \
    AETHER_NETSTACK_TCP_RX=2097152 \
    AETHER_NETSTACK_TCP_TX=2097152

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

RUN cat <<'EOF' > /entrypoint.sh
#!/usr/bin/env bash
set -u

export PORT="${PORT:-8080}"
export AETHER_BIND="${AETHER_BIND:-127.0.0.1:1819}"
export AETHER_CONFIG="${AETHER_CONFIG:-/data/aether.toml}"
export AETHER_SCAN="${AETHER_SCAN:-balanced}"
export AETHER_PROTOCOL="${AETHER_PROTOCOL:-masque}"
export AETHER_NETSTACK_TCP_RX="${AETHER_NETSTACK_TCP_RX:-2097152}"
export AETHER_NETSTACK_TCP_TX="${AETHER_NETSTACK_TCP_TX:-2097152}"

CADDY_PID=""
XRAY_PID=""
AETHER_PID=""

cleanup() {
    local exit_code="${1:-0}"
    trap - SIGTERM SIGINT SIGHUP EXIT
    kill -TERM "$CADDY_PID" "$XRAY_PID" "$AETHER_PID" 2>/dev/null || true
    wait "$CADDY_PID" "$XRAY_PID" "$AETHER_PID" 2>/dev/null || true
    exit "$exit_code"
}

trap 'cleanup 143' SIGTERM
trap 'cleanup 130' SIGINT
trap 'cleanup 129' SIGHUP

mkdir -p /etc/caddy /data /var/log/gateway

if [ -f /etc/xray/config.json ]; then
    sed -i 's/"port": 8080/"port": 10001/g' /etc/xray/config.json 2>/dev/null || true
    sed -i 's/"port": 8081/"port": 10002/g' /etc/xray/config.json 2>/dev/null || true
    sed -i 's/"port": 8082/"port": 10003/g' /etc/xray/config.json 2>/dev/null || true
    sed -i 's/"listen": "0.0.0.0"/"listen": "127.0.0.1"/g' /etc/xray/config.json 2>/dev/null || true
fi

cat <<CADDYCONF > /etc/caddy/Caddyfile
{
    admin off
    auto_https off
}

:${PORT} {
    log {
        output discard
    }
    reverse_proxy /api/v1/live* 127.0.0.1:10001
    reverse_proxy /api/v1/gateway* 127.0.0.1:10002
    reverse_proxy /api/v1/sync* 127.0.0.1:10003
    root * /var/www/html
    file_server
}
CADDYCONF

echo "[ORCHESTRATOR] Spawning Aether MASQUE Core (TCP Netstack Boost: 2MB Buffers)..."
/usr/local/bin/aether \
    --bind "${AETHER_BIND}" \
    --${AETHER_PROTOCOL} \
    --h2 \
    -4 \
    --scan "${AETHER_SCAN}" \
    --config "${AETHER_CONFIG}" &
AETHER_PID=$!

/usr/local/bin/xray run -config /etc/xray/config.json &
XRAY_PID=$!

/usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
CADDY_PID=$!

SUPERVISOR_STATUS=0
wait -n "$CADDY_PID" "$XRAY_PID" "$AETHER_PID" || SUPERVISOR_STATUS=$?
cleanup "${SUPERVISOR_STATUS}"
EOF

RUN chmod +x /entrypoint.sh

COPY config.json /etc/xray/config.json

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
