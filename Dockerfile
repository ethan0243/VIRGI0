# ==============================================================================
# BERMUDA x AETHER Core Gateway - Hardened Production Container
# Architecture: Multi-Stage Hybrid (Xray-core + Aether MASQUE Core + Caddy Ingress)
# Target Environment: Railway Cloud PaaS / GitHub Automated CI/CD
# ==============================================================================

# ------------------------------------------------------------------------------
# STAGE 1: Artifact Fetcher & Validation Engine
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim AS builder

ARG TARGETARCH

# نصب ابزارهای ضروری برای دانلود و استخراج بسته‌ها
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/build

# دانلود و نصب امن باینری‌های رسمی متناسب با معماری پردازنده
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

# نصب نیازمندی‌های زمان اجرا (Runtime Essentials)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    procps \
    curl \
    && rm -rf /var/lib/apt/lists/*

# انتقال باینری‌ها و دیتابیس‌ها از استیج‌های بیلدر
COPY --from=builder /usr/local/bin/xray /usr/local/bin/xray
COPY --from=builder /usr/local/share/xray /usr/local/share/xray
COPY --from=builder /usr/local/bin/aether /usr/local/bin/aether
COPY --from=caddy-source /usr/bin/caddy /usr/local/bin/caddy

# ساخت دایرکتوری‌های عملیاتی با مجوز دسترسی مناسب
RUN mkdir -p /etc/xray /data /var/www/html /var/log/gateway \
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

# کپی فایل کانفیگ فاز ۱ و اسکریپت استارت فاز ۳
COPY config.json /etc/xray/config.json
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

# اکسپوز پورت پیش‌فرض (توسط ریلوی با متغیر PORT همگام می‌شود)
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
