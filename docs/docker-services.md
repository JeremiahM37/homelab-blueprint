# Docker Services (LXC 200)

All services run on a single privileged LXC container (12 cores, 24 GB RAM) using Docker Compose. The compose file defines two networks: `proxy` (for externally-accessible services) and `internal` (for backend databases and inter-service communication).

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
| **shelfarr** | 5056 | Book wishlist + tracker | Tracks wanted books, sends to Librarr |
| **librarr** | 5050 | Book search + download | Custom Flask app (via VPN) |
| **lncrawl** | — | Web novel scraper | Batch job, no persistent port |

### Games

| Container | Port | Purpose | Notes |
|-----------|------|---------|-------|
| **gamarr** | 5057 | Game/ROM search + download | Custom Flask app (via VPN) |
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

### Infrastructure & Monitoring

| Container | Port | Purpose | Notes |
|-----------|------|---------|-------|
| **homepage** | 3000 | Dashboard | Aggregates all service status |
| **uptime-kuma** | 3001 | Uptime monitoring | HTTP/TCP/ping checks |
| **n8n** | 5678 | Workflow automation | Watchdog workflows, health checks |
| **portainer** | 9000 | Docker management UI | |
| **grafana** | 3060 | Metrics dashboard | |
| **prometheus** | — | Metrics collection | Internal |
| **cadvisor** | — | Container metrics | Feeds Prometheus |
| **node-exporter** | — | Host metrics | Feeds Prometheus |
| **crowdsec** | — | Intrusion detection | |
| **watchtower** | — | Auto-update containers | |
| **autoheal** | — | Auto-restart unhealthy containers | |
| **pulse** | 7655 | Server stats | |
| **cloudflared** | — | Cloudflare tunnel | Public access to select services |
| **docker-socket-proxy** | 2375 | Docker socket for n8n | Read-only proxy |
| **discord-bot** | 3003 | Discord notifications | |

---

## Architecture Notes

### VPN Routing

Services that need VPN protection use Docker's `network_mode: "service:gluetun"`. This means:

- The container shares gluetun's network namespace
- All traffic routes through the WireGuard tunnel
- Ports must be exposed on the gluetun container, not the service itself
- If gluetun restarts, dependent containers lose networking

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
- Media data: `/data/media/` (bind mount from DAS via host)
- Downloads: Through gluetun network, written to `/data/media/` subdirectories

### PUID/PGID

Most containers run as UID/GID 1000. Download directories must be owned by `1000:1000` or you'll get permission errors (especially visible as qBittorrent "error" state).

### Health Checks

- **autoheal** restarts containers with failing Docker health checks
- **n8n workflows** monitor critical services (qBit, gluetun VPN, *arr apps)
- **media-monitor agent** (on separate LXC) runs periodic health checks with LLM-assisted remediation
