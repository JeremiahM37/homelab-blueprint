# Docker Services (LXC 200)

All services run on a single unprivileged LXC container (12 cores, 24 GB RAM) using Docker Compose. The compose file defines two networks: `proxy` (for externally-accessible services) and `internal` (for backend databases and inter-service communication).

---

## Service Map

### Media Automation

| Container | Port | Purpose | Notes |
|-----------|------|---------|-------|
| **jellyfin** | 8096 | Media server (movies, TV, music) | Hardware transcoding via iGPU |
| **sonarr** | 8989 | TV show management + automation | Monitors RSS, sends to download client |
| **radarr** | 7878 | Movie management + automation | Same pattern as Sonarr |
| **bazarr** | 6767 | Subtitle management | Integrates with Sonarr/Radarr |
| **prowlarr** | 9696 | Indexer/tracker manager | Central indexer config for all *arr apps |
| **jellyseerr** | 5055 | Media request portal | User-facing request UI → Sonarr/Radarr |
| **tdarr** | 8265 | Automated transcoding | Batch re-encode library to target codec/size |

### Books & Reading

| Container | Port | Purpose | Notes |
|-----------|------|---------|-------|
| **audiobookshelf** | 13378 | Audiobook + podcast server | OPDS support |
| **calibre-web** | 8083 | Ebook library (OPDS) | Backed by Calibre database |
| **kavita** | 5005 | Comic / manga reader | Separate from ebook library |
| **librarr** | 5050 | Book search, request, and download manager | Go binary (17 MB), 13 search sources, user request/approval workflow, search result scoring, Open Library metadata enrichment (covers, series, descriptions), admin dashboard with activity log, file uploads, 4 download clients (qBit/SABnzbd/Deluge/Transmission), Torznab/OPDS APIs, TOTP 2FA, OIDC/SSO, Prometheus metrics |
| **sentinel** | 9200 | Download guardian + library verification | Go binary (11 MB), SQLite persistence, multi-source fallback, definitive library verification (Jellyfin/ABS/Kavita/Sonarr/Radarr), Discord notifications |
| **lncrawl** | — | Web novel scraper | Batch job, no persistent port |

### Games

| Container | Port | Purpose | Notes |
|-----------|------|---------|-------|
| **gamarr** | 5057 | Game/ROM search + download | Go binary, 24 platforms, Prowlarr+Myrient+Vimm sources (via VPN) |
| **gamevault** | 8087 | PC game library server | With PostgreSQL backend |
| **romm** | 8086 | ROM manager | With MariaDB backend |

### Downloading & Networking

| Container | Port | Purpose | Notes |
|-----------|------|---------|-------|
| **gluetun** | 8001 | VPN container (WireGuard) | All download clients route through this |
| **qbittorrent** | 8080 | Torrent client | Runs inside gluetun network namespace |
| **flaresolverr** | — | Cloudflare bypass | Internal only, used by Prowlarr |
| **unpackerr** | — | Auto-extract downloads | Monitors qBit completed directory |

### Productivity & Tools

| Container | Port | Purpose | Notes |
|-----------|------|---------|-------|
| **paperless** | 8000 | Document management / OCR | With Redis backend |
| **mealie** | 9925 | Recipe manager | |
| **homebox** | 7745 | Home inventory tracker | |
| **linkwarden** | 3050 | Bookmark / link manager | With PostgreSQL backend |
| **changedetection** | 5100 | Website change monitor | With headless Chrome |
| **stirling-pdf** | 8084 | PDF tools | |
| **it-tools** | 8085 | Developer utilities | |
| **lab** | 8099 | Disposable mini-app / widget host | Single-binary Go static server + flat-file KV store; add/remove apps via a registry, installable PWA |

### Files, photos and household tools

| Container | Port | Purpose | Notes |
|-----------|------|---------|-------|
| **seafile** | 8082 | File sync/share | MariaDB + memcached; private deployment bypasses login |
| **immich-server** | 2283 | Photo/video library | ML worker, PostgreSQL and Redis |
| **firefly** | 8091 | Personal finance | PostgreSQL and cron worker |
| **firefly-importer** | 8092 | Import bank/CSV data | Companion to Firefly |
| **jellystat** | 8093 | Viewing analytics | PostgreSQL backend |
| **grocy** | 8094 | Pantry and household inventory | |

Notes moved to **Grimoire on AIServer (9111)**. SilverBullet and its MCP bridge
are retired. Syncthing now runs natively on AIServer for the live notes vault.

### Search

| Container | Port | Purpose | Notes |
|-----------|------|---------|-------|
| **searxng** | 8888 | Self-hosted web search | JSON API, powers AI agent + Homepage search |

### SSO / Reverse Proxy

| Container | Port | Purpose | Notes |
|-----------|------|---------|-------|
| **nginx-proxy** | 80, 443 | Reverse proxy | Service gateways on `*.homelab.internal`, self-signed wildcard cert (10-year) |
| **authelia** | 9091 | SSO identity provider | File-based auth, one-factor, session cookie for `.homelab.internal` |

### Infrastructure & Monitoring

| Container | Port | Purpose | Notes |
|-----------|------|---------|-------|
| **homepage** | 3000 | Dashboard | AI chat widget, SearXNG search, disk usage widgets |
| **uptime-kuma** | 3001 | Uptime monitoring | HTTP/TCP/ping checks |
| **n8n** | 5678 | Workflow automation | Watchdog workflows, health checks |
| **portainer** | 9000 | Docker management UI | |
| **grafana** | 3060 | Metrics dashboard | |
| **prometheus** | — | Metrics collection | Internal |
| **cadvisor** | — | Container metrics | Feeds Prometheus |
| **loki / promtail** | 3100 / — | Logs | Collection and querying |
| **omada-controller / snmp-exporter** | Host networking / internal | Managed switch | Network management and metrics |
| **chroma** | 8200 | Vector storage | Doc RAG backend |
| **node-exporter** | — | Host metrics | Feeds Prometheus |
| **crowdsec** | — | Intrusion detection | |
| **watchtower** | — | Auto-update containers | |
| **autoheal** | — | Auto-restart unhealthy containers | |
| **pulse** | 7655 | Server stats | |
| **cloudflared** | — | Cloudflare tunnel | Public access to select services |
| **docker-socket-proxy** | 2375 | Docker socket for n8n | Selected Docker API operations; permits configured writes |
| **discord-bot** | 3003 | Discord notifications | |

---

## Host services outside Docker

| Host / guest | Service |
|--------------|---------|
| AIServer | Homelab API/PWA (9105), Grimoire (9111), Lectern (9110 / TLS 8443), Formwork (9113), Doc RAG (9103), Syncthing |
| LXC 100 | Homelab Agent (9106) |
| LXC 102 | Ollama and Open WebUI |
| LXC 107 | Agent Desk browser, desktop and MCP gateway |

## Architecture Notes

### VPN Routing

Services that need VPN protection use Docker's `network_mode: "service:gluetun"`. This means:

- The container shares gluetun's network namespace
- All traffic routes through the WireGuard tunnel
- Ports must be exposed on the gluetun container, not the service itself
- If Gluetun is recreated, dependents can retain the old namespace; the deployed namespace guard recreates them after the VPN is healthy

```yaml
# Example pattern
gluetun:
  image: qmcgaw/gluetun
  ports:
    - "8080:8080"   # qBittorrent
    - "5050:5050"   # Librarr
    - "5057:5001"   # Gamarr (host:container port mapping)

qbittorrent:
  network_mode: "service:gluetun"
  depends_on:
    - gluetun
```

### Database Backends

Several services use dedicated database containers on the `internal` network:

- **romm** → MariaDB
- **gamevault** → PostgreSQL
- **linkwarden** → PostgreSQL
- **paperless** → Redis

### Volume Strategy

- Config data: `/opt/docker/{service}/` on LXC filesystem
- Media data: `/mnt/storage` is passed into LXC 200; `/data/media` resolves to its media tree
- Downloads: Through gluetun network, written to `/data/media/` subdirectories

### PUID/PGID

Most containers run as UID/GID 1000. Download directories must be owned by `1000:1000` or you'll get permission errors (especially visible as qBittorrent "error" state).

### SSO Integration

Browser-facing services are accessible via `https://<service>.homelab.internal` through the nginx reverse proxy. Common authentication patterns are:

- **Tier 1 — True SSO**: Sonarr, Radarr, Prowlarr, Bazarr, Grafana, n8n, Paperless trust the `Remote-User` header from Authelia (no service login needed)
- **Tier 2 — Authelia gate**: Homepage, it-tools, Stirling PDF, Tdarr, Pulse, Sentinel have no built-in auth; Authelia is the sole protection
- **Tier 3 — Passthrough**: Jellyfin, qBittorrent, Audiobookshelf, Kavita, Portainer, etc. use their own login; nginx proxies without `auth_request`

The private Seafile deployment additionally bypasses its own login; do not copy that behavior to an exposed installation.

API calls from the Homelab API / Agent use direct IP:port (bypassing nginx) — SSO only applies to browser access.

### Health Checks

- **autoheal** restarts containers with failing Docker health checks
- **n8n workflows** monitor critical services (qBit, gluetun VPN, *arr apps)
- **Homelab Agent** (on LXC 100) runs periodic health checks every 5 min with 3-tier LLM-assisted remediation
