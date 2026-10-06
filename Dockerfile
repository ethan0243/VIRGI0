# syntax=docker/dockerfile:1
# ==============================================================================
# BERMUDA x AETHER Core Gateway - Hardened Production Container
# Architecture: Multi-Stage Hybrid (Xray-core + Aether MASQUE Core + Caddy Ingress)
# Camouflage: High-Fidelity Infrastructure Documentation Landing Page
# Optimization: Netstack 2MB Buffers + Zero-RTT DNS Routing Strategy
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

LABEL maintainer="AetherCore Distributed Systems" \
      description="High-Throughput Asynchronous Network Ingress & Transit Node" \
      version="10.2-stealth"

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

# صفحه دکوی استتار سازمانی کاملاً واقعی (Realistic High-Fidelity Decoy Page)
RUN cat <<'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AetherCore · Next-Gen Distributed Transit Framework</title>
    <style>
        :root { --bg: #090a0f; --card: #12141c; --border: #1f2333; --accent: #38bdf8; --text: #f1f5f9; --muted: #94a3b8; }
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        body { background-color: var(--bg); color: var(--text); line-height: 1.6; min-height: 100vh; display: flex; flex-direction: column; }
        header { border-bottom: 1px solid var(--border); padding: 18px 40px; display: flex; justify-content: space-between; align-items: center; background: rgba(9,10,15,0.8); backdrop-filter: blur(12px); }
        .logo { font-weight: 800; font-size: 1.15rem; letter-spacing: -0.5px; color: var(--accent); display: flex; align-items: center; gap: 8px; }
        .status-badge { background: rgba(16,185,129,0.12); color: #10b981; border: 1px solid rgba(16,185,129,0.3); padding: 4px 12px; border-radius: 99px; font-size: 0.75rem; font-weight: 600; font-family: monospace; }
        main { flex: 1; max-width: 1000px; margin: 60px auto; padding: 0 24px; text-align: center; }
        h1 { font-size: 2.8rem; font-weight: 800; letter-spacing: -1.2px; margin-bottom: 16px; background: linear-gradient(180deg, #fff 0%, #94a3b8 100%); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        p.lead { font-size: 1.15rem; color: var(--muted); max-width: 650px; margin: 0 auto 40px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 20px; text-align: left; margin-top: 40px; }
        .card { background: var(--card); border: 1px solid var(--border); padding: 24px; border-radius: 14px; }
        .card h3 { font-size: 1rem; color: var(--accent); margin-bottom: 8px; font-weight: 600; }
        .card p { font-size: 0.88rem; color: var(--muted); }
        footer { border-top: 1px solid var(--border); padding: 24px; text-align: center; font-size: 0.8rem; color: var(--muted); font-family: monospace; }
    </style>
</head>
<body>
    <header>
        <div class="logo">◈ AetherCore Engine</div>
        <div class="status-badge">● CLUSTER NODE ONLINE · 200 OK</div>
    </header>
    <main>
        <h1>Asynchronous Micro-Transit Gateway</h1>
        <p class="lead">High-performance edge router orchestrating encrypted packet streaming, micro-routing pipelines, and zero-loss multiplexing.</p>
        <div class="grid">
            <div class="card">
                <h3>RFC 9298 MASQUE Ingress</h3>
                <p>Multiplexed Application Substrate delivering high-throughput datagram transit with low overhead and kernel-level socket isolation.</p>
            </div>
            <div class="card">
                <h3>Zero-RTT Edge Caching</h3>
                <p>Distributed Anycast interconnect fabric executing instantaneous DNS and payload routing across global infrastructure zones.</p>
            </div>
            <div class="card">
                <h3>Hardened Pipeline Security</h3>
                <p>TLS 1.3 cryptographic termination, automatic flow-control windows, and strict isolated process supervision.</p>
            </div>
        </div>
    </main>
    <footer>
        Node ID: rlwy-prod-transit-01 · API Gateway v10.2 · Apache-2.0 Open Infrastructure
    </footer>
</body>
</html>
EOF

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
