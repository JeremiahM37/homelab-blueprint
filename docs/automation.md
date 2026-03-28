# Automation & AI

Everything built to run autonomously with minimal human intervention.

---

## Discord AI Bot

A custom Discord bot (`discord-bot` container, port 3003) with a local LLM-powered `*ai` command that routes natural language to 64+ tools across 15+ services.

### Architecture

```
Discord message
  → *ai <anything>
  → qwen3:1.7b on Ollama (LXC 102, AMD iGPU) — intent parsing
  → Route to /api/ai/jarvis (tool-calling agent)
  → qwen3.5:35b-a3b decides which tools to call
  → Execute against homelab APIs
  → Response back to Discord
```

### Performance
- Intent parsing: **<1 second** (think mode disabled)
- Tool-calling agent: 2-10 seconds depending on tool chain complexity
- System prompt: ~1,141 tokens, 64+ tools
- Model: qwen3:1.7b (~1.4GB) for intent, qwen3.5:35b-a3b (23GB) for agent
- Cost: **$0** (local inference)

### Supported Actions

| Category | Actions |
|----------|---------|
| Media requests | movie, tv, book, audiobook (via Jellyseerr/Librarr Go/Sentinel) |
| PDF tools | compress, merge, convert to images, add page numbers, rotate (via Stirling PDF) |
| Photos | upload to Immich, create albums, search, list albums |
| Documents | upload to Paperless, search, tag, set correspondents |
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
| Gaming | search games, download ROMs, sync status, Bazzite VM status |
| Web search | SearXNG-powered web search |
| Diagnostics | file checks, log reading, permission fixes, library rescans |
| Verification | definitive library verification with proof |
| System | status, downloads, storage, now playing, recent, backups |

### Service Clients
Located in `/opt/docker/discord-bot/services/`:
- stirling.py, immich.py, paperless.py, seafile.py, mealie.py
- kavita_client.py, homebox.py, abs_client.py
- changedetection_client.py, tdarr_client.py
- sonarr_extra.py, radarr_extra.py, qbit_client.py

---

## Sentinel (Download Guardian)

**Sentinel** is a standalone Go binary (11 MB) that acts as the download guardian and library verifier. It replaced the previous Python-based guardian that was embedded in the homelab API.

Sentinel monitors the full pipeline from content request to library arrival with definitive verification (file paths, runtimes, page counts -- not fuzzy title matching). It runs as its own Docker container on port 9200.

### How It Works

1. **Request**: User asks for a book/movie/game via any interface
2. **Guardian job**: Sentinel creates a SQLite-backed job record
3. **State machine**: Jobs advance through `PENDING -> SEARCHING -> DOWNLOADING -> VERIFYING -> COMPLETED`
4. **Multi-source**: Tries sources in priority order per media type
   - Books: Librarr (13 sources) -> Prowlarr
   - Movies/TV: Jellyseerr (routes to Sonarr/Radarr)
   - Games: Gamarr torrent -> Myrient direct download
5. **Library verification**: Checks target library with real API calls and returns proof
6. **Escalation**: If all sources fail, AI agent can use diagnostic tools to investigate

### API (port 9200)

| Endpoint | Purpose |
|----------|---------|
| `POST /api/jobs` | Create a new guardian job |
| `GET /api/jobs` | List all jobs |
| `GET /api/jobs/{id}` | Detailed status of a specific job |
| `POST /api/jobs/{id}/cancel` | Cancel a job |
| `POST /api/jobs/{id}/retry` | Retry a failed job |
| `GET /api/stats` | Job statistics |
| `POST /api/verify` | One-shot library verification |

### Persistence

Jobs survive restarts because state is in SQLite. The Go rewrite compiles to a single static binary (scratch Docker image) with zero runtime dependencies.

---

## Homelab Unified API

A FastAPI service on AIServer (port 9105) that aggregates ALL homelab services into one REST API.

### Key Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /api/overview` | Everything at a glance (temps, watching, speeds, backups) |
| `GET /api/system/temps` | All 3 nodes' temperatures |
| `GET /api/system/storage` | Per-node disk usage (used/free/total/percent) |
| `GET /api/system/storage/{node}` | Specific node storage |
| `POST /api/system/backup/{target}` | Trigger backup for a specific target |
| `GET /api/media/now-playing` | Jellyfin active streams |
| `GET /api/media/calendar` | Upcoming episodes + movies |
| `GET /api/downloads/speed` | qBit transfer speeds |
| `POST /api/ai/jarvis` | Tool-calling AI agent |
| `POST /api/ai/chat` | Chat with local LLM |
| `GET /api/ai/ask-docs?q=...` | RAG query over documents |
| `GET /api/verify/check` | Verify item in specific library |
| `GET /api/verify/check-all` | Verify item across all libraries |
| `/api/diag/*` | Diagnostic tools (file ops, logs, rescans) |
| `/api/gaming/*` | Game search, download, sync status |
| `/api/documents/tags` | Paperless tag management |
| `/docs` | Swagger UI (interactive API explorer) |

Full endpoint list at `GET /`.

---

## Document RAG

Vector search over Paperless documents using local embeddings + LLM generation.

- **Embedding**: nomic-embed-text (~275MB) on Ollama
- **Generation**: qwen3:1.7b on Ollama
- **Vector DB**: ChromaDB (persistent, on disk)
- **Indexed**: 169 documents -> 11,357 chunks
- **Port**: 9103 on AIServer
- **Privacy**: NOT exposed via Discord — admin-only via API or direct access

### Usage
```bash
# Ask a question
curl "http://YOUR_AISERVER_IP:9103/api/ask?q=direct+deposit+info"

# Re-index after adding new Paperless docs
curl -X POST http://YOUR_AISERVER_IP:9103/api/reindex
```

---

## Dual-Channel Discord Alerts

All automated systems send notifications to **both** Discord servers simultaneously:

- n8n watchdog workflows (VM watchdog, container watchdog, VPN leak, etc.)
- Media monitor agent (health events, auto-fixes)
- Download Guardian (job status updates)
- Backup status alerts

This ensures alerts are seen regardless of which Discord server is being monitored.

---

## Automated Backups

Restic backups to the DAS, encrypted and deduplicated.

- **Repo**: `/mnt/storage/backups/homelab` on MediaServer DAS
- **Schedule**: Daily at 3AM (systemd timers on each node)
- **Retention**: 7 daily / 4 weekly / 3 monthly
- **Status API**: port 9102 on MediaServer host
- **Trigger API**: `POST /api/system/backup/{target}` on the unified API (port 9105)

### What's Backed Up
| Source | Contents |
|--------|----------|
| LXC 200 | Docker configs, compose files, service databases (excludes media/caches) |
| AIServer | Home dir, Proxmox config, LXC definitions, systemd services |
| pve | Proxmox config, SSH keys, GRUB, VFIO/modprobe configs |
| MediaServer | Proxmox config, SSH keys |

### Triggering Backups

Backups can be triggered manually via the unified API:

```bash
curl -X POST http://YOUR_AISERVER_IP:9105/api/system/backup/aiserver
curl -X POST http://YOUR_AISERVER_IP:9105/api/system/backup/lxc200
```

The AI agent can also trigger backups via natural language ("back up the AI server").

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
Checks -> LLM analyzes results -> decides simple fix or human alert -> executes -> Discord notification

---

## Homelab Agent (Proactive Autonomous Monitoring)

A proactive monitoring agent on AIServer (port 9106) that scans the entire homelab every 15 minutes.

### Modules

| Module | Purpose | Frequency |
|--------|---------|-----------|
| **Container Doctor** | Monitors 14 key containers, auto-restarts, crash loop detection | Every 15 min |
| **Source Intelligence** | Checks all 13 Librarr search sources, tracks availability | Every 60 min |
| **Import Watchdog** | Detects stuck downloads and failed imports, auto-retries | Every 15 min |
| **AI Escalation** | Escalates complex failures to `/api/ai/jarvis` for AI diagnosis | On failure |
| **Download Notifications** | Checks Sonarr/Radarr history for new completions, posts Discord embeds with poster art | Every 15 min |
| **Release Watcher** | Searches web for new releases from watched series/authors | Every 60 min |

### Design

- SQLite failure memory prevents repeating failed fixes
- Conversation memory persists chat history per channel (Discord, Homepage, etc.)
- User preference learning tracks download patterns (authors, genres)
- Separate from media-monitor (LXC 100) which handles reactive health checks
- Discord notifications for all actions (download completions include poster thumbnails)

---

## Nightly Tests (45 tests, 5 AM daily)

Comprehensive end-to-end test suite validating every service.

- **Timer**: `nightly-tests.timer` / `nightly-tests.service`
- **Coverage**: HTTP health checks, API endpoint validation, SSH connectivity, Docker container status, Proxmox cluster health
- **Runtime**: ~48 seconds for all 45 tests
- **Notification**: Results posted to Discord with pass/fail summary

---

## Temperature Monitoring

Tiny Python HTTP APIs on each node (port 9101) serving hardware sensor data as JSON. Powers the Homepage dashboard "Server Temps" section.

Service: `systemctl status temp-api` on each node.
