# Steel Browser on Railway — wrapper around the pinned upstream image.
#
# Why a wrapper at all (house style: bake constants, keep the deploy
# form minimal, and survive Railway's root-owned volumes):
# - AUTH GATEWAY (the reason this template exists): upstream Steel
#   Browser ships NO authentication of any kind — no API key, no
#   bearer token, no basic auth anywhere in its code (verified by
#   code search 2026-11-11; the README warns "Ports 3000 and 9223
#   have no authentication. Don't expose them to the public
#   internet"). The official Railway template (steelbrowser, 357
#   deploys) ships that unauthenticated setup and its own page says
#   only "consider adding authentication". This wrapper puts an nginx
#   gateway on Railway's injected PORT (gateway/nginx.conf.template)
#   and requires the generated STEEL_API_KEY on every route except
#   GET /v1/health (the platform probe). The key is accepted as
#   Authorization: Bearer, x-api-key, steel-api-key, ?apiKey= (for
#   CDP WebSocket clients, which cannot send headers), or a cookie
#   set by /login — the cookie is what keeps the built-in /ui
#   session viewer working, which a header-only gateway breaks.
#   /devtools/ is proxied through the gateway to the internal CDP
#   nginx so the debugger URL works too. entrypoint.sh renders the
#   gateway config at boot and refuses to start without a key.
# - PORT: Steel honors Railway's PORT (api/src/index.ts), but the
#   gateway must own the public port, so entrypoint.sh moves Steel
#   to internal port 12732 and the gateway listens on Railway's
#   PORT. Never set a startCommand: the image ENTRYPOINT is tini +
#   the upstream entrypoint script, which execs node directly.
# - USER root: the published image config carries no USER directive
#   (verified via the GHCR registry API 2026-11-11), so it already
#   runs as root, but the wrapper states USER root explicitly so a
#   future upstream non-root switch cannot silently break writes to
#   Railway's root-owned volume (browser logs live on /data).
# - DATA: one Railway volume at /data. LOG_STORAGE_ENABLED=true and
#   LOG_STORAGE_PATH=/data/logs/browser-logs.duckdb (baked below,
#   as in upstream's docker-compose.yml) put Steel's DuckDB session
#   logs on the volume so they survive restarts. Sessions themselves
#   are ephemeral by design — no database, no companion service.
# - PUBLIC URL: derived at boot from the live RAILWAY_PUBLIC_DOMAIN
#   by entrypoint.sh (DOMAIN + USE_SSL=true) — never a
#   template-expression variable. Steel builds session websocket
#   URLs from DOMAIN; without it the API hands clients
#   ws://localhost:... URLs they cannot reach. (Same shape as the
#   2026-10-29 Spliit BASE_URL and 2026-11-08 LLDAP HTTP_URL
#   lessons.)
# - HEALTHCHECK: upstream's own GET /v1/health — returns
#   {"status":"ok"} when Chromium is up, 503 while it is still
#   starting. It is the one route the gateway leaves open, so
#   Railway's probe works without a key.
# - No Docker HEALTHCHECK: rely on Railway's external
#   healthcheckPath.
#
# Upstream: Steel Browser v0.5.5-beta (Apache-2.0), combined API+UI
# image ghcr.io/steel-dev/steel-browser, pinned by manifest index
# digest, verified 2026-11-11 via the GHCR registry API (multi-arch
# amd64+arm64; built 2026-11-09, matching upstream's latest push;
# amd64 manifest sha256:eefa89d4...; image config: no USER, ports
# 3000+9223, entrypoint tini + /app/api/entrypoint.sh, NODE_ENV
# =production so the UI is served at /ui). The `latest` tag carries
# no versioned tag — the digest IS the pin.
# NOTE: the FROM uses the digest WITHOUT a tag — Railpack 0.43.0
# fails to detect a Dockerfile whose FROM carries both a tag and a
# digest (redeploys die in the plan phase with "could not determine
# how to build the app"); the digest-only form builds under both
# the Dockerfile builder and Railpack (verified 2026-11-05 —
# TimeTagger's digest-only FROM is the precedent).

# ghcr.io/steel-dev/steel-browser:latest (built 2026-11-09)
FROM ghcr.io/steel-dev/steel-browser@sha256:a49bea54bfb5ff249c62c05d11df18fa1340138d201448e7c536f70c01cfaa94

USER root

COPY entrypoint.sh /app/entrypoint.sh
COPY gateway/nginx.conf.template /app/gateway/nginx.conf.template
COPY gateway/login.html /usr/share/steel-gateway/login.html
RUN chmod +x /app/entrypoint.sh

# Baked constants (see header): persistent browser logs on the
# volume. The HTTP port is split by the entrypoint on every boot
# (Steel internal 12732, gateway on Railway's PORT).
ENV LOG_STORAGE_ENABLED=true \
    LOG_STORAGE_PATH=/data/logs/browser-logs.duckdb

# Documentation only: the gateway listens on Railway's injected
# $PORT at runtime (see entrypoint.sh); 9223 is the internal CDP
# debugger port, proxied by the gateway as /devtools/.
EXPOSE 9223

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
