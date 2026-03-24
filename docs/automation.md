# Automation & AI

Everything built to run autonomously with minimal human intervention.

---

## Discord AI Bot

A custom Discord bot (`discord-bot` container, port 3003) with a local LLM-powered `*ai` command that routes natural language to 30+ actions across 15 services.

### Architecture

```
Discord message
  → *ai <anything>
  → qwen3:1.7b on Ollama (LXC 102, AMD iGPU)
  → JSON intent: {"action": "movie", "query": "dune", "message": "Searching!"}
  → Route to service API
  → Response back to Discord
```

### Performance
- Intent parsing: **<1 second** (think mode disabled)
- System prompt: ~1,141 tokens, 30+ actions
- Model: qwen3:1.7b (~1.4GB), auto-unloads after 2 minutes idle
- Accuracy: ~96% on test suite
- Cost: **$0** (local inference)

### Supported Actions

| Category | Actions |
|----------|---------|
| Media requests | movie, tv, book, audiobook (via Jellyseerr/Librarr) |
| PDF tools | compress, merge, convert to images, add page numbers, rotate (via Stirling PDF) |
| Photos | upload to Immich, create albums, search, list albums |
| Documents | upload to Paperless, search Paperless |
| Cloud storage | upload to Seafile, list files, create folders, search |
| Recipes | search Mealie, import from URL, random recipe, meal plan |
| Comics/manga | search Kavita, recently added, continue reading |
| Audiobook library | search Audiobookshelf, recently added |
| Home inventory | search Homebox, list locations |
| Website monitoring | add watch, list watches, recent changes (Changedetection) |
| Transcoding | Tdarr stats |
| TV calendar | Sonarr upcoming episodes, missing episodes |
| Movie calendar | Radarr upcoming movies, missing movies |
| Torrents | speed, list, pause all, resume all (qBittorrent) |
| Library search | search what's already in Jellyfin |
| System | status, downloads, storage, now playing, recent |

### Service Clients
Located in `/opt/docker/discord-bot/services/`:
- stirling.py, immich.py, paperless.py, seafile.py, mealie.py
- kavita_client.py, homebox.py, abs_client.py
- changedetection_client.py, tdarr_client.py
- sonarr_extra.py, radarr_extra.py, qbit_client.py

---

## Homelab Unified API

A FastAPI service on AIServer (port 9105) that aggregates ALL homelab services into one REST API.

### Key Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /api/overview` | Everything at a glance (temps, watching, speeds, backups) |
| `GET /api/system/temps` | All 3 nodes' temperatures |
| `GET /api/media/now-playing` | Jellyfin active streams |
| `GET /api/media/calendar` | Upcoming episodes + movies |
| `GET /api/downloads/speed` | qBit transfer speeds |
| `POST /api/ai/chat` | Chat with local LLM |
| `GET /api/ai/ask-docs?q=...` | RAG query over documents |
| `/docs` | Swagger UI (interactive API explorer) |

Full endpoint list at `GET /`.

---

## Document RAG

Vector search over Paperless documents using local embeddings + LLM generation.

- **Embedding**: nomic-embed-text (~275MB) on Ollama
- **Generation**: qwen3:1.7b on Ollama
- **Vector DB**: ChromaDB (persistent, on disk)
- **Indexed**: 169 documents → 11,357 chunks
- **Port**: 9103 on AIServer
- **Privacy**: NOT exposed via Discord — admin-only via API or direct access

### Usage
```bash
# Ask a question
curl "http://153.90.84.228:9103/api/ask?q=direct+deposit+info"

# Re-index after adding new Paperless docs
curl -X POST http://153.90.84.228:9103/api/reindex
```

---

## Automated Backups

Restic backups to the DAS, encrypted and deduplicated.

- **Repo**: `/mnt/storage/backups/homelab` on MediaServer DAS
- **Schedule**: Daily at 3AM (systemd timers on each node)
- **Retention**: 7 daily / 4 weekly / 3 monthly
- **Status API**: port 9102 on MediaServer host

### What's Backed Up
| Source | Contents |
|--------|----------|
| LXC 200 | Docker configs, compose files, service databases (excludes media/caches) |
| AIServer | Home dir, Proxmox config, LXC definitions, systemd services |
| pve | Proxmox config, SSH keys, GRUB, VFIO/modprobe configs |
| MediaServer | Proxmox config, SSH keys |

---

## CrowdSec (Intrusion Prevention)

Active firewall-level IP blocking using community threat intelligence.

- **Agent**: Docker container in LXC 200, API on port 8081
- **Bouncer**: `crowdsec-firewall-bouncer` on MediaServer HOST (iptables mode)
- **Active blocks**: ~1,400+ malicious IPs
- **Scenarios**: SSH brute force, HTTP CVE exploits, DoS, bad user agents, path traversal, SQLi, XSS
- **Community API**: Connected to CrowdSec's shared blocklist (200k+ installations)

---

## Terraform (Infrastructure as Code)

Entire cluster defined as Terraform config using the bpg/proxmox provider.

- **Location**: `/home/admin/terraform/` on AIServer
- **State**: All 7 LXCs + LXC 200 + VM 103 imported
- **Status API**: port 9104 on AIServer
- **Purpose**: Disaster recovery — if a node dies, `terraform apply` recreates everything

---

## Media Monitor (AI Self-Healing Agent)

LXC 100 runs an autonomous monitoring agent that checks the entire media pipeline every 5 minutes.

### What It Monitors
- Container health (all 55+ containers)
- qBittorrent torrent health (error, stalled, dead)
- VPN connectivity (gluetun)
- DAS mount status
- Disk space + forecast
- Crash loops
- Prowlarr indexer health
- Sonarr/Radarr queue issues

### Auto-Fix Actions
- Restart crashed containers (with crash-loop guard)
- Restart gluetun + qBit on VPN stalls
- Fix file permissions
- Blacklist bad releases in Sonarr/Radarr (triggers auto re-search)
- Reannounce stalled torrents
- Search Prowlarr for replacement torrents when originals die
- Remove dead manual torrents after failed replacement
- Test and disable broken Prowlarr indexers

### How It Works
Checks → LLM analyzes results → decides simple fix or human alert → executes → Discord notification

---

## Temperature Monitoring

Tiny Python HTTP APIs on each node (port 9101) serving hardware sensor data as JSON. Powers the Homepage dashboard "Server Temps" section.

Service: `systemctl status temp-api` on each node.
