# Dust Diesel: Public Web + Nakama via Cloudflare Tunnel

This guide explains how to share your local `dust_diesel` build with friends over the internet.

It covers:
- Running Nakama locally with Docker Compose
- Exporting the Godot Web build
- Exposing both services with Cloudflare Quick Tunnels
- Sharing the correct URL so the browser build uses the Nakama tunnel

## 1) Prerequisites

- `docker` + `docker compose`
- `godot` (4.6)
- `cloudflared`
- `python3`

## 2) Start backend services

From project root:

```bash
docker compose up -d
docker compose ps
```

Confirm `nakama` is healthy and mapped on `7350`.

## 3) Export web build

From project root:

```bash
godot --headless --path . --export-release "Web" ./builds/web/index.html
```

Expected output files:
- `builds/web/index.html`
- `builds/web/index.js`
- `builds/web/index.wasm`
- `builds/web/index.pck`

## 4) Start local web server for build

```bash
python3 -m http.server 8000 --directory ./builds/web --bind 127.0.0.1
```

Keep this terminal open.

## 5) Start Cloudflare tunnel for Nakama

In a new terminal:

```bash
cloudflared tunnel --no-autoupdate --url http://127.0.0.1:7350
```

Copy the generated `https://...trycloudflare.com` URL.
This is your `NAKAMA_TUNNEL_URL`.

## 6) Start Cloudflare tunnel for web build

In another new terminal:

```bash
cloudflared tunnel --no-autoupdate --url http://127.0.0.1:8000
```

Copy the generated `https://...trycloudflare.com` URL.
This is your `WEB_TUNNEL_URL`.

## 7) Share the correct game URL

Always pass Nakama endpoint explicitly in query params:

```text
WEB_TUNNEL_URL/?nakama_host=<nakama-host>&nakama_port=443&nakama_scheme=https
```

Example:

```text
https://your-web.trycloudflare.com/?nakama_host=your-nakama.trycloudflare.com&nakama_port=443&nakama_scheme=https
```

Why this matters:
- Without these params, the web build may try local defaults (`127.0.0.1`) or wrong host.
- If auth hits the wrong server, you may see `501` on `/v2/account/authenticate/device`.

## 8) Common issues

### `Secure Context` error
- Use the Cloudflare `https://` URL, not `file://` and not plain LAN `http://`.

### `Device ID is required`
- Ensure your build includes the web device ID fallback fix in `scripts/network/nakama_manager.gd`.
- Hard refresh browser (`Ctrl+Shift+R`) to avoid stale JS.

### `501` on `/v2/account/authenticate/device`
- You are likely sending Nakama API requests to the web tunnel host.
- Use the query-param URL format from section 7.

### Tunnels changed suddenly
- Quick Tunnel URLs are temporary and rotate when restarted.
- Restart and share updated URLs.

## 9) Stop everything

Stop the two tunnel terminals and the web server terminal with `Ctrl+C`.

Backend:

```bash
docker compose down
```

## 10) Recommended next step (stable URLs)

Use a **named tunnel** in Cloudflare Zero Trust with your domain:
- Example hosts:
  - `game.yourdomain.com` -> local `127.0.0.1:8000`
  - `nakama.yourdomain.com` -> local `127.0.0.1:7350`

Then share:

```text
https://game.yourdomain.com/?nakama_host=nakama.yourdomain.com&nakama_port=443&nakama_scheme=https
```

