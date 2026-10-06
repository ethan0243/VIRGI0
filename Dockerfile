# syntax=docker/dockerfile:1.7

# ------------------------------------------------------------------------------
# Stage 1: Static Go 1.24 Gateway Compiler
# ------------------------------------------------------------------------------
FROM golang:1.24-bookworm AS builder

ARG TARGETARCH=amd64

WORKDIR /src

COPY go.mod ./
COPY main.go proxy.go supervisor.go ./

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) export GOARCH=amd64 GOAMD64=v2 ;; \
        arm64) export GOARCH=arm64 GOARM64=v8.0 ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    CGO_ENABLED=0 GOOS=linux \
    go build \
        -trimpath \
        -tags netgo,osusergo \
        -ldflags="-s -w -buildid=" \
        -o /out/bermuda-gateway .; \
    chmod 0555 /out/bermuda-gateway

# ------------------------------------------------------------------------------
# Stage 2: Dual Core Artifact Fetcher (Xray-Core & Aether MASQUE)
# ------------------------------------------------------------------------------
FROM ubuntu:24.04 AS artifact-downloader

ARG TARGETARCH=amd64
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/downloads

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) XRAY_ARCH="64"; AETHER_ARCH="x86_64" ;; \
        arm64) XRAY_ARCH="arm64-v8a"; AETHER_ARCH="arm64" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o xray.zip; \
    mkdir -p /out/bin /out/assets; \
    unzip -q xray.zip xray -d /out/bin; \
    unzip -q xray.zip geoip.dat geosite.dat -d /out/assets; \
    \
    curl -fsSL "https://github.com/CluvexStudio/Aether/releases/latest/download/aether-linux-${AETHER_ARCH}.tar.gz" -o aether.tar.gz; \
    tar -xzf aether.tar.gz -C /out/bin; \
    chmod 0555 /out/bin/xray /out/bin/aether; \
    chmod 0444 /out/assets/*.dat

# ------------------------------------------------------------------------------
# Stage 3: Hardened Rootless Runtime (Ubuntu 24.04 with Native GLIBC 2.39)
# ------------------------------------------------------------------------------
FROM ubuntu:24.04

LABEL maintainer="BERMUDA Institutional Core" \
      description="Hardened L7 Edge Gateway & WARP MASQUE Chained Outbound Engine" \
      version="3.0-production"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    PORT=8080 \
    XRAY_LOCATION_ASSET=/usr/local/share/xray \
    BERMUDA_XRAY_BIN=/usr/local/bin/xray \
    BERMUDA_XRAY_CONFIG=/app/config.json \
    BERMUDA_AETHER_BIN=/usr/local/bin/aether \
    AETHER_CONFIG=/data/aether.toml \
    AETHER_NETSTACK_TCP_RX=2097152 \
    AETHER_NETSTACK_TCP_TX=2097152 \
    BERMUDA_BACKEND_XH=127.0.0.1:18443 \
    BERMUDA_BACKEND_WS=127.0.0.1:18444 \
    BERMUDA_BACKEND_TR=127.0.0.1:18445 \
    BERMUDA_BACKEND_WARP=127.0.0.1:1819 \
    BERMUDA_PATH_XH=/api/v1/sync \
    BERMUDA_PATH_WS=/api/v1/live \
    BERMUDA_PATH_TR=/api/v1/gateway \
    BERMUDA_HEALTH_PATH=/.well-known/hc-5b1e7c \
    GODEBUG=madvdontneed=1 \
    GOGC=100

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    curl \
    procps \
    && rm -rf /var/lib/apt/lists/*; \
    groupadd -g 10001 bermuda; \
    useradd -u 10001 -g bermuda -d /app -s /usr/sbin/nologin bermuda; \
    mkdir -p /app /data /usr/local/share/xray /usr/local/bin /tmp; \
    chown -R bermuda:bermuda /data /tmp; \
    chmod 770 /data; \
    chmod 1777 /tmp

COPY --from=builder /out/bermuda-gateway /usr/local/bin/bermuda-gateway
COPY --from=artifact-downloader /out/bin/xray /usr/local/bin/xray
COPY --from=artifact-downloader /out/bin/aether /usr/local/bin/aether
COPY --from=artifact-downloader /out/assets/geoip.dat /usr/local/share/xray/geoip.dat
COPY --from=artifact-downloader /out/assets/geosite.dat /usr/local/share/xray/geosite.dat
COPY config.json /app/config.json

RUN chmod 0555 /usr/local/bin/bermuda-gateway /usr/local/bin/xray /usr/local/bin/aether; \
    chmod 0444 /app/config.json /usr/local/share/xray/geoip.dat /usr/local/share/xray/geosite.dat

USER 10001:10001
WORKDIR /app

EXPOSE 8080
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS -o /dev/null "http://127.0.0.1:${PORT:-8080}/.well-known/hc-5b1e7c" || exit 1

ENTRYPOINT ["/usr/local/bin/bermuda-gateway"]
