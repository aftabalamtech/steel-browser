#!/bin/sh
# Steel Browser Railway wrapper entrypoint.
#
# What it does, in order:
# - PORT SPLIT: Railway injects PORT at runtime and routes the public
#   domain to it. Steel itself honors PORT (verified in
#   steel-dev/steel-browser api/src/index.ts: `process.env.PORT ?
#   parseInt(...) : 3000`), but the nginx gateway must own the public
#   port, so Steel is moved to an internal port (12732 — chosen to
#   never collide with Railway's injected value) and the gateway
#   listens on Railway's PORT. Capture the public port FIRST, before
#   remapping PORT for Steel.
# - AUTH: the gateway needs STEEL_API_KEY. Refuse to start without it
#   — an unauthenticated Steel instance is an open proxy, and starting
#   one "temporarily" is how it ships. The key must be alphanumeric
#   (Railway ${{secret(32)}} is); anything else would break the nginx
#   map values it is rendered into, so fail loud instead of starting
#   a gateway that cannot match the key.
# - PUBLIC URL: derive DOMAIN and USE_SSL at boot from the live
#   RAILWAY_PUBLIC_DOMAIN. Steel builds the session websocketUrl and
#   debugger URL from DOMAIN (api/src/utils/url.ts: getBaseUrl uses
#   `env.DOMAIN ?? HOST:PORT`, and HOST defaults to 0.0.0.0, which
#   becomes localhost) — without this the API hands clients
#   ws://localhost:... URLs they cannot reach. Only set them when a
#   real domain is present; a https://${{RAILWAY_PUBLIC_DOMAIN}}
#   template default would resolve to a bare "https://" on first
#   deploy (no domain exists yet). (Same shape as the 2026-10-29
#   Spliit BASE_URL and 2026-11-08 LLDAP HTTP_URL lessons.)
#   USE_SSL=true because Railway terminates TLS at the edge and the
#   container only ever sees plain HTTP — without it Steel returns
#   http:// / ws:// URLs for an https:// deployment.
# - LOGS: enable Steel's DuckDB log storage on the volume
#   (/data/logs/browser-logs.duckdb, as in upstream's
#   docker-compose.yml) so session logs survive restarts. The
#   baked Dockerfile ENV carries the same values; the exports here
#   are the live ones.
# - GATEWAY CONFIG: render gateway/nginx.conf.template into
#   /app/api/nginx.conf (the path upstream's entrypoint starts nginx
#   with) using node — split/join, not sed, so no key character can
#   break the substitution. Validate with `nginx -t` before handing
#   off; a bad gateway config must fail the deploy, not silently
#   serve nothing.
# - HANDOFF: exec upstream's entrypoint.sh, which starts nginx (our
#   rendered config, including the 9223 CDP server) and then execs
#   `node ./api/build/index.js`. Our ENTRYPOINT already runs under
#   tini as PID 1, so signals and zombie reaping stay correct.

set -eu

PUBLIC_PORT="${PORT:-8080}"
KEY="${STEEL_API_KEY:-}"

case "$KEY" in
  '')
    echo "Steel: FATAL STEEL_API_KEY is not set; refusing to start an unauthenticated browser." >&2
    exit 1
    ;;
  *[!A-Za-z0-9]*)
    echo "Steel: FATAL STEEL_API_KEY must be alphanumeric (Railway \${{secret(32)}} is); refusing to start." >&2
    exit 1
    ;;
esac

# Steel listens internally on 12732; the gateway owns Railway's PORT.
export PORT=12732

# PUBLIC URL: derive at boot from the live RAILWAY_PUBLIC_DOMAIN.
# Only set it when a real domain is present.
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  export DOMAIN="${RAILWAY_PUBLIC_DOMAIN}"
  export USE_SSL=true
fi

# Persistent browser logs on the volume.
export LOG_STORAGE_ENABLED=true
export LOG_STORAGE_PATH=/data/logs/browser-logs.duckdb
mkdir -p /data/logs || { echo "Steel: ERROR /data not available; refusing to start." >&2; exit 1; }

# Render the gateway config (node is in the image).
PUBLIC_PORT="$PUBLIC_PORT" STEEL_API_KEY="$KEY" node -e '
const fs = require("fs");
let s = fs.readFileSync("/app/gateway/nginx.conf.template", "utf8");
s = s.split("__PUBLIC_PORT__").join(process.env.PUBLIC_PORT);
s = s.split("__STEEL_API_KEY__").join(process.env.STEEL_API_KEY);
fs.writeFileSync("/app/api/nginx.conf", s);
'

nginx -t -c /app/api/nginx.conf || { echo "Steel: FATAL gateway nginx config failed validation; refusing to start." >&2; exit 1; }

echo "Steel: gateway on :${PUBLIC_PORT}, Steel API on :12732 (internal), logs in /data/logs"
exec /app/api/entrypoint.sh "$@"
