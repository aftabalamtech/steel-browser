# Steel Browser

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/deploy/steel-browser-1?utm_campaign=steel-browser)

Steel Browser is the open-source browser API for AI agents and apps: a batteries-included headless Chromium behind a REST API, with sessions, scraping, screenshots, PDFs, and a raw Chrome DevTools Protocol WebSocket that Puppeteer and Playwright connect to directly. This template deploys it as a single service — **API-key locked on every route**, so the public URL is a private browser endpoint, not an open proxy.

![Steel Browser — live session viewer](assets/steel-ui.png)

*Steel's live session viewer — frame from upstream's demo (`.github/assets/demo.gif`, steel-dev/steel-browser).*

## Source Repository

[https://github.com/INAPP-Mobile/steel-browser](https://github.com/INAPP-Mobile/steel-browser)

## Deploy and Host

One-click deploy creates a single Steel Browser service with a persistent volume for browser logs. After deploy, open the public URL: `/login` validates the generated `STEEL_API_KEY` against the POST-only session creation endpoint, then stores it as a cookie and unlocks the browser UI (`/ui`) in that browser; API clients send the same key as an `Authorization: Bearer`, `x-api-key`, or `?apiKey=` credential. `GET /v1/health` stays open so the platform health check works without a key.

## Why Deploy

- **Private by default:** upstream Steel ships no authentication of any kind — the official Railway template leaves the browser API open to anyone who finds the URL. This wrapper puts an nginx gateway in front of every route, so your Chromium, your sessions, and your IP are yours alone. The key is generated per deploy; rotate it in the Railway variables panel.
- **The UI actually works locked:** a header-only gateway would lock the built-in session viewer out of its own API. The `/login` page validates the key using POST (not GET) and stores it as a cookie, so the live session viewer, session-cast WebSockets, the Swagger docs at `/documentation`, and the DevTools debugger at `/devtools/` all work in the browser after one login.
- **Correct URLs out of the box:** the wrapper derives the public domain and TLS setting at boot, so the `websocketUrl` and debugger URLs Steel hands back are reachable `wss://` URLs — not `ws://localhost:...`.
- **Pinned and reproducible:** the image is pinned by manifest digest, not `:latest`, so a redeploy never silently pulls a new upstream build.
- **Logs persist:** Steel's DuckDB session logs live on a Railway volume at `/data/logs`, so they survive restarts.

## Common Use Cases

- A browser backend for AI agents that browse, click, and read the live web.
- Headless scraping, screenshots, and PDF generation over a simple REST API.
- A remote CDP endpoint for Puppeteer or Playwright (`connect` over the returned WebSocket URL).
- A shared, authenticated browser for scripts and services running in the same Railway project.
- Watching a live session in the built-in viewer while an agent works.

## Configuration

Only `STEEL_API_KEY` is on the deploy form (generated). Everything else is baked into the image or derived at boot.

| Variable | Default | Description |
| --- | --- | --- |
| `STEEL_API_KEY` | `${{secret(32)}}` | API key for every route except `GET /v1/health`. Generated per deploy. Send as `Authorization: Bearer`, `x-api-key`, `steel-api-key`, or `?apiKey=`; or open `/login` in a browser to unlock the UI with it. The wrapper refuses to start without it. |
| `DOMAIN` | (derived from `RAILWAY_PUBLIC_DOMAIN` at boot) | Public domain Steel advertises in session and debugger URLs. Set manually only for a custom domain. |
| `USE_SSL` | `true` when a public domain exists | Makes Steel return `https://` / `wss://` URLs. Railway terminates TLS at the edge, so the container only ever sees plain HTTP. |
| `LOG_STORAGE_ENABLED` | `true` | Enables Steel's DuckDB session-log storage. Baked into the image. |
| `LOG_STORAGE_PATH` | `/data/logs/browser-logs.duckdb` | Session logs on the volume. Baked into the image. |
| `PORT` | (split at boot) | Railway's injected port is owned by the nginx gateway; Steel listens internally on 12731. |
| `PROXY_URL` | — | (Upstream, optional) Proxy Steel routes browser traffic through, e.g. `user:pass@host:port`. |
| `DEFAULT_HEADERS` | `{}` | (Upstream, optional) JSON object of headers added to every browser request. |
| `CHROME_EXECUTABLE_PATH` | `/usr/bin/chromium` | (Upstream, optional) Custom Chrome/Chromium binary path. |
| `CHROME_HEADLESS` | `true` | (Upstream, optional) Headless mode. |
| `CHROME_ARGS` | — | (Upstream, optional) Extra space-separated Chrome flags. |
| `FILTER_CHROME_ARGS` | — | (Upstream, optional) Space-separated Chrome flags to strip from Steel's defaults. |
| `DISABLE_CHROME_SANDBOX` | — | (Upstream, optional) Set to `true` only if Chromium cannot start in the container. |
| `DEFAULT_TIMEZONE` | — | (Upstream, optional) Timezone for browser sessions, e.g. `America/New_York`. |
| `SKIP_FINGERPRINT_INJECTION` | — | (Upstream, optional) Set to `true` to disable Steel's fingerprint injection. |
| `ENABLE_COMMANDS_API` | — | (Upstream, optional) Set to `true` to enable the experimental Commands API. |
| `ENABLE_CDP_LOGGING` | — | (Upstream, optional) Set to `true` to log CDP traffic. |
| `ENABLE_VERBOSE_LOGGING` | — | (Upstream, optional) Set to `true` for verbose Fastify logging. |
| `LOG_LEVEL` | `debug` | (Upstream, optional) Log level (development logging only). |
| `KILL_TIMEOUT` | `0` | (Upstream, optional) ms to wait for a session browser to die before force-killing. |

## API quickstart

```bash
# Create a session (replace $DOMAIN and $KEY)
curl -X POST "https://$DOMAIN/v1/sessions" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"blockAds": true, "dimensions": {"width": 1280, "height": 800}}'

# Scrape a page to markdown
curl -X POST "https://$DOMAIN/v1/scrape" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'

# Health (no key needed)
curl "https://$DOMAIN/v1/health"
```

Full API reference: the Swagger UI at `https://$DOMAIN/documentation` (key required), or [docs.steel.dev](https://docs.steel.dev).

## How it works

Steel Browser (Apache-2.0, [steel-dev/steel-browser](https://github.com/steel-dev/steel-browser)) runs a Fastify API on an internal port with a bundled Chromium. This wrapper adds an nginx gateway on Railway's injected port that requires `STEEL_API_KEY` on every route except `GET /v1/health`, serves the `/login` page that stores the key as a cookie for the browser UI, and proxies `/devtools/` to the internal CDP debugger. The image is pinned by manifest digest (`sha256:a49bea54…`, built 2026-11-09).

### Deployment Dependencies

- Plan tier: Hobby is enough for a single session at a time; each Chromium session adds memory — a few hundred MB per session — so size up if you run many concurrent sessions.
- One persistent volume mounted at `/data` (browser logs at `/data/logs/browser-logs.duckdb`).
- No companion database, no extra services. Sessions are ephemeral by design.
- The DevTools console debugger port (9223) is internal-only: Railway exposes a single public port per service, so the debugger is reached through the gateway as `/devtools/` instead.
