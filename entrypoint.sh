#!/usr/bin/env bash
# ==============================================================================
# BERMUDA x AETHER Core Gateway - Process Orchestrator & Lifecycle Supervisor
# Architecture: Multi-Daemon Orchestration (Aether MASQUE -> Xray -> Caddy)
# Target Environment: Railway Cloud PaaS / Container Runtime
# ==============================================================================

set -u

# ------------------------------------------------------------------------------
# 1. مقداردهی متغیرهای محیطی و مقادیر پیش‌فرض
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# 2. مدیریت سیگنال‌های خاتمه و خاموش‌سازی ایمن (Graceful Shutdown)
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# 3. تولید داینامیک پیکربندی Caddy بر اساس پورت ریلوی
# ------------------------------------------------------------------------------
mkdir -p /etc/caddy /data /var/log/gateway

echo "[ORCHESTRATOR] Synthesizing dynamic reverse-proxy matrix for Port :${PORT}..."
cat <<EOF > /etc/caddy/Caddyfile
{
    admin off
    auto_https off
}

:${PORT} {
    log {
        output discard
    }

    # Ingress Route 1: VLESS WebSocket Pipeline
    reverse_proxy /api/v1/live* 127.0.0.1:8080

    # Ingress Route 2: Trojan WebSocket Pipeline
    reverse_proxy /api/v1/gateway* 127.0.0.1:8081

    # Ingress Route 3: VLESS XHTTP Pipeline
    reverse_proxy /api/v1/sync* 127.0.0.1:8082

    # Decoy Masquerade Asset: Anti-Probing 200 OK Response
    root * /var/www/html
    file_server
}
EOF

# ------------------------------------------------------------------------------
# 4. مرحله الف: اجرای دیمون خروجی Aether WARP MASQUE
# ------------------------------------------------------------------------------
echo "[ORCHESTRATOR] Spawning Aether MASQUE Core on ${AETHER_BIND}..."
/usr/local/bin/aether \
    --bind "${AETHER_BIND}" \
    --${AETHER_PROTOCOL} \
    -4 \
    --scan "${AETHER_SCAN}" \
    --quick-reconnect \
    --config "${AETHER_CONFIG}" &
AETHER_PID=$!

echo "[ORCHESTRATOR] Aether daemon active (PID: ${AETHER_PID})."

# ------------------------------------------------------------------------------
# 5. مرحله ب: اجرای هسته سوئیچینگ و احراز هویت Xray
# ------------------------------------------------------------------------------
echo "[ORCHESTRATOR] Spawning Xray Switching Core (/etc/xray/config.json)..."
/usr/local/bin/xray run -config /etc/xray/config.json &
XRAY_PID=$!

echo "[ORCHESTRATOR] Xray core active (PID: ${XRAY_PID})."

# ------------------------------------------------------------------------------
# 6. مرحله ج: اجرای گیت‌وی ورودی Caddy روی پورت ریلوی
# ------------------------------------------------------------------------------
echo "[ORCHESTRATOR] Spawning Caddy Edge Ingress Gateway on Port :${PORT}..."
/usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
CADDY_PID=$!

echo "[ORCHESTRATOR] Caddy ingress active (PID: ${CADDY_PID}). Edge router listening."

# ------------------------------------------------------------------------------
# 7. اعتبارسنجی ناهمگام پورت SOCKS5 خروجی (Non-blocking IPC Probe)
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# 8. حلقه نظارت پیوسته بر حیات پروسه‌ها (Supervisor Monitoring)
# ------------------------------------------------------------------------------
echo "[ORCHESTRATOR] Cluster Gateway online and operational. Monitoring process health..."

SUPERVISOR_STATUS=0
wait -n "$CADDY_PID" "$XRAY_PID" "$AETHER_PID" || SUPERVISOR_STATUS=$?

echo "[ORCHESTRATOR] Detected termination of core process (Exit Status: ${SUPERVISOR_STATUS})."
cleanup "${SUPERVISOR_STATUS}"
