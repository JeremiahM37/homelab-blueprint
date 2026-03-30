# AI / ML Stack

Multiple dedicated LXC containers on a 128 GB RAM node for running local LLMs, ML research, AI experiments, and AI-powered automation. The centerpiece is a **tool-calling AI agent** that controls the entire homelab via natural language, backed by a **3-tier AI repair system** that autonomously fixes issues.

---

## Architecture

```
AIServer (128 GB RAM, 32 cores, Ryzen AI MAX+ 395, Radeon 8060S iGPU)
│
├── LXC 102 — "openclaw" (28 GB — LLM Chat)
│   ├── Ollama (model serving, 2min idle timeout)
│   │   ├── qwen3.5:35b-a3b (34.5 GB on GPU, chat + tool calling)
│   │   ├── qwen3:1.7b (6.2 GB on GPU, intent parsing + Tier 1 repairs)
│   │   ├── nomic-embed-text (275 MB, document RAG embeddings)
│   │   └── qwen3:4b, qwen3:0.6b (available, not active)
│   ├── Open-WebUI (chat interface, port 8080)
│   │   └── SearXNG integration (AI web search)
│   │   └── MCP tools (Proxmox + Homelab management)
│   └── MCP tools proxy (Proxmox management from chat)
│
├── LXC 105 — "research-env" (16 GB — ML Research)
│   ├── GPU passthrough (Radeon 8060S via ROCm)
│   ├── PyTorch 2.9.1 + ROCm 7.12 (native gfx1151)
│   └── Full scientific Python stack
│
├── LXC 106 — "ai-detector" (12 GB — AI Detection)
│   ├── GPU passthrough (shared iGPU)
│   └── DeBERTa fine-tuning for AI text detection
│
├── Host services:
│   ├── Homelab API (port 9105) — unified FastAPI with AI agent (64+ tools)
│   │   ├── /api/ai/jarvis — tool-calling agent endpoint
│   │   ├── /api/guardian/* — proxies to Go Sentinel
│   │   ├── /api/verify/* — proxies to Go Sentinel library verification
│   │   ├── /api/diag/* — diagnostic tools
│   │   ├── /api/gaming/* — game search + download
│   │   └── /api/system/storage — per-node disk usage
│   ├── Homelab Agent (port 9106) — proactive autonomous monitoring (7 modules)
│   │   ├── Container doctor (14 containers, auto-restart)
│   │   ├── Source intelligence (13 Librarr sources, hourly)
│   │   ├── Import watchdog (stuck downloads, failed imports)
│   │   ├── Torrent doctor (qBit health, VPN stalls, dead torrent replacement, game auto-organize)
│   │   ├── System monitor (DAS, disk forecasting, host load, container resources)
│   │   ├── Notifications (deduplication, resolved alerts, weekly digest)
│   │   └── AI escalation (3-tier repair: 1.7b → 35b → Claude Code)
│   ├── Document RAG (port 9103) — vector search over Paperless docs
│   ├── Terraform status (port 9104) — IaC state API
│   └── Temp API (port 9101) — hardware sensor data
│
├── SearXNG (runs on LXC 200, port 8888)
│   ├── Connected to Open WebUI for AI web search
│   ├── Connected to Homepage search widget
│   └── JSON API at /search?q=...&format=json
│
└── Discord Bot AI (runs on LXC 200, calls Ollama on LXC 102)
    └── *ai command — 64+ tools via agent loop
```

### GPU (AMD 8060S iGPU — Unified Memory)

The Radeon 8060S on Strix Halo uses **GTT (Graphics Translation Table) memory** — a unified memory architecture that allows models to be loaded fully on GPU using system RAM.

- **61.7 GB GTT available** — both active models load entirely into GPU memory
- `qwen3.5:35b-a3b`: 34.5 GB on GPU, ~22 ms/token
- `qwen3:1.7b`: 6.2 GB on GPU, ~8 ms/token
- Models run **fully GPU-accelerated** via GTT, not CPU-only
- Shared across LXCs 102, 105, 106 via /dev/dri + /dev/kfd passthrough
- Not exclusive like RTX 2070 on pve (fully owned by VM 103)

---

## AI Tool-Calling Agent

The `/api/ai/jarvis` endpoint is a full tool-calling agent — not just a chat wrapper. It uses Ollama's native tool calling with qwen3.5:35b-a3b to decide which actions to take, execute them, and synthesize results.

### Agent Loop (Intent Routing)

```
User message (any interface)
  └── qwen3:1.7b intent classifier
        ├── "chat" → qwen3:1.7b generates simple response (~8ms/token)
        └── "action" → qwen3:1.7b tool calling (64+ tools, sub-second parsing)
              └── Execute tool calls against homelab APIs
                    └── Feed results back to LLM
                          └── Generate response (or make more tool calls)

Homelab Agent detects issue
  └── Tier 1: qwen3:1.7b tries Jarvis tools (fast, <1 second)
        └── fails → Tier 2: qwen3.5:35b-a3b smart fixer (think: true, 19 tools)
              └── fails → Tier 3: writes fix-request.md → Claude Code (every 5 hours)
```

### Interfaces

The same agent brain powers three interfaces:

| Interface | Access | Notes |
|-----------|--------|-------|
| **Discord bot** | `*ai <anything>` in Discord | Sub-second intent parsing via qwen3:1.7b, then routes to agent |
| **Homepage chat widget** | Floating bubble on dashboard | Custom JS/CSS with tool-call progress indicators |
| **Mobile PWA** | `/app` endpoint | AI chat with 120s timeout for mobile use |
| **Open WebUI** | MCP tools via mcpo proxy | Full chat UI with conversation history |

### Tool Categories (64+)

| Category | Tools | Examples |
|----------|-------|---------|
| **Web search** | SearXNG integration | Search the web, summarize results |
| **Media control** | Jellyfin, Sonarr, Radarr, Jellyseerr | Now playing, calendar, request movies/TV |
| **Downloads** | qBittorrent, gluetun | Speed, list torrents, pause/resume all |
| **Books** | Librarr (Go), Audiobookshelf, Calibre, Kavita | Search 13 sources, download, request, wishlist |
| **Guardian** | Sentinel (Go) | Create guardian jobs, check status, verify library arrival |
| **Documents** | Paperless | Search, tag, set correspondents, RAG queries, **AI auto-tag** |
| **Photos** | Immich | Search, list albums, upload |
| **Recipes** | Mealie | Search, **import from URL**, random, **meal plan** |
| **Inventory** | Homebox | Search items, list locations |
| **Gaming** | Gamarr, Bazzite | Search games, download ROMs, VM status, sync status |
| **Monitoring** | Changedetection | **Add/remove/list URL watches**, website changes |
| **Bookmarks** | Linkwarden | **Save URLs, search bookmarks, list collections** |
| **Containers** | Docker on LXC 200 | **List, restart, stop, start** individual containers |
| **Diagnostics** | File ops, logs, rescans | Check files, fix permissions, read container logs |
| **Verification** | Sentinel library checks | Verify items exist with real API proof (file paths, durations, page counts) |
| **System** | Temps, storage, backups | Per-node disk usage, trigger backups, sensor data |
| **Transcoding** | Tdarr | Stats, queue status |
| **Memory** | Conversation + preferences | Chat history, **watchlist for new releases**, preference learning |

---

## 3-Tier AI Repair System

The homelab uses a tiered approach to autonomous repair, escalating from fast/cheap to slow/powerful only when needed.

### Tier 1 — Fast Tool Calls (qwen3:1.7b)

- **Model**: qwen3:1.7b (~8 ms/token, 6.2 GB on GPU)
- **When**: First response to any detected issue
- **How**: Calls Jarvis API tools directly — restart containers, fix permissions, rescan libraries, search/download, check status
- **Handles**: ~90% of issues in under 1 second
- **Example**: Container crashed → restart via Docker API → verify it came back → done

### Tier 2 — Smart Fixer (qwen3.5:35b-a3b)

- **Model**: qwen3.5:35b-a3b with `think: true` (~22 ms/token, 34.5 GB on GPU)
- **When**: Tier 1 failed or the issue requires deeper reasoning
- **Tools (19)**: Read/edit files, run commands on LXC 200 and AIServer, manage torrents, rebuild Docker containers, Prowlarr search, library verification
- **Safety**: Backs up files before editing, logs all actions to `audit_log.md`
- **Example**: Import pipeline broken → read container logs → identify config issue → edit config file (with backup) → rebuild container → verify fix

### Tier 3 — Claude Code (Scheduled)

- **When**: Runs every 5 hours on a schedule
- **What**: Reviews Tier 2's `audit_log.md` and reverts bad changes. Handles anything Tiers 1 and 2 couldn't fix. Picks up `fix-request.md` files written by the agent.
- **Example**: Tier 2 edited a config incorrectly → Claude Code reviews the audit log → reverts the change → applies correct fix → updates documentation

### Escalation Flow

```
Issue detected by Homelab Agent
  │
  ├── Tier 1: qwen3:1.7b (instant, tool calls)
  │     ├── Fixed? → log + notify → done
  │     └── Failed? → escalate
  │
  ├── Tier 2: qwen3.5:35b-a3b (think: true, 19 tools)
  │     ├── Fixed? → log to audit_log.md + notify → done
  │     └── Failed? → write fix-request.md → escalate
  │
  └── Tier 3: Claude Code (every 5 hours)
        ├── Review audit_log.md → revert bad changes
        ├── Pick up fix-request.md → investigate + fix
        └── Handle anything Tiers 1+2 couldn't
```

---

## Sentinel (Download Guardian)

**Sentinel** is a standalone Go binary (11 MB) that acts as the download guardian and library verifier for the entire media pipeline. It replaced the previous Python-based guardian built into the homelab API.

Sentinel monitors the full pipeline from content request to library arrival. When you request a movie, book, or audiobook, Sentinel watches the download, verifies it actually landed in your library with **definitive proof** (file paths, runtimes, page counts), and tries alternative sources if one fails.

### Source Priority

| Media Type | Source Order |
|------------|-------------|
| **Books** | Librarr (13 sources) -> Prowlarr |
| **Movies/TV** | Jellyseerr (routes to Sonarr/Radarr) |
| **Games** | Gamarr torrent -> Myrient (direct download) |

### Job Lifecycle

```
Request received
  └── Create guardian job in SQLite (survives restarts)
        └── PENDING → SEARCHING → try sources in priority order
              ├── DOWNLOADING → monitor qBittorrent progress
              │     └── VERIFYING → check library for proof of arrival
              │           └── COMPLETED (with proof: file path, runtime, page count)
              └── Source failed → try next source
                    └── All sources exhausted → FAILED + Discord notification
                          └── AI agent can use diagnostic tools to investigate
```

### API Endpoints (port 9200)

| Endpoint | Purpose |
|----------|---------|
| `POST /api/jobs` | Create a new guardian job |
| `GET /api/jobs` | List all jobs |
| `GET /api/jobs/{id}` | Detailed status of a specific job |
| `POST /api/jobs/{id}/cancel` | Cancel a job |
| `POST /api/jobs/{id}/retry` | Retry a failed job |
| `GET /api/stats` | Job statistics |
| `POST /api/verify` | One-shot library verification (no job) |
| `GET /health` | Health check |

---

## Library Verification (Sentinel)

Sentinel's verification system performs **definitive** checks — real API calls with proof, not fuzzy title matching. This is used both by guardian jobs (automatic) and one-shot verification requests.

### Per-Library Checks

| Library | What It Checks | Proof |
|---------|---------------|-------|
| **Jellyfin** | Items API | File path + runtime |
| **Audiobookshelf** | Library items | `isMissing=false` + audio file count + duration |
| **Kavita** | Series search | Page count > 0 + folder path |
| **Sonarr** | Series lookup | Episode file count > 0 + series path |
| **Radarr** | Movie lookup | `hasFile=true` + file path + size |

### Endpoints (on Sentinel, port 9200)

| Endpoint | Purpose |
|----------|---------|
| `POST /api/verify` | One-shot verification with proof |

The AI agent also exposes verification through the unified API at `/api/verify/check` and `/api/verify/check-all`.

---

## Diagnostic Tools

Available at `/api/diag/*` for AI escalation when automated processes fail. These execute on LXC 200 via SSH.

| Endpoint | Purpose |
|----------|---------|
| `POST /api/diag/check_file_exists` | Verify a file/directory exists |
| `POST /api/diag/list_directory` | List contents of a directory |
| `POST /api/diag/extract_archive_recursive` | Extract nested archives |
| `POST /api/diag/move_file` | Move/rename files |
| `POST /api/diag/fix_permissions` | Fix ownership (chown 1000:1000) |
| `POST /api/diag/read_container_logs` | Read Docker container logs |
| `POST /api/diag/rescan_library` | Trigger library rescan (Jellyfin/ABS/Kavita) |

### Escalation Flow

```
Download Guardian fails
  └── AI agent detects failure
        └── Uses diagnostic tools to investigate
              ├── Check if file exists on disk
              ├── Read container logs for errors
              ├── Fix permissions if needed
              ├── Trigger library rescan
              └── Report findings to user
```

---

## Homelab Agent (Proactive Autonomous Monitoring)

A proactive monitoring agent running on AIServer (port 9106) that scans the entire homelab every 5 minutes, detecting and fixing issues before they become visible to the user. Uses the 3-tier AI repair system for escalation.

### Architecture

```
systemd service (continuous, 5min scan loop)
  └── agent.py
        ├── container_doctor — monitors 14 key containers, auto-restart, crash loop detection
        ├── source_intelligence — checks 13 Librarr search sources hourly, tracks availability
        ├── import_watchdog — stuck downloads, failed imports, auto-retry
        ├── torrent_doctor — qBit health, VPN stall detection, orphan routing, dead torrent replacement
        ├── system_monitor — DAS mount, disk space + 7-day forecasting, host load/RAM, container resources
        ├── notifications — alert deduplication, resolved notifications, rate limiting, weekly digest
        └── ai_escalation — 3-tier repair (1.7b → 35b → Claude Code)
```

### Modules

| Module | Purpose | Frequency |
|--------|---------|-----------|
| **Container Doctor** | Monitors 14 key containers, auto-restarts crashed ones, crash loop guard | Every 5 min |
| **Source Intelligence** | Checks all 13 Librarr sources, tracks availability, detects outages | Every 60 min |
| **Import Watchdog** | Detects stuck downloads and failed imports, auto-retries | Every 5 min |
| **Torrent Doctor** | qBit health checks, VPN stall detection, dead torrent replacement (0 seeds >5 min → search Gamarr/Prowlarr for alternative), game auto-organize (incoming → vault), Gamarr stuck/failed job retry, orphan routing, ratio-limit checks | Every 5 min |
| **System Monitor** | DAS mount verification, disk space with 7-day forecasting, host load/RAM, container resource outliers, Prowlarr indexer auto-retry, Tdarr/Unpackerr/Cloudflared monitoring, n8n workflow checks, download directory permissions | Every 5 min |
| **Notifications** | Fingerprint-based alert deduplication, resolved notifications, rate limiting, weekly digest | Continuous |
| **AI Escalation** | 3-tier repair system — Tier 1 (1.7b fast tools) → Tier 2 (35b smart fixer) → Tier 3 (Claude Code) | On failure |

### Failure Memory

- SQLite database tracks all failures and remediation attempts
- Prevents repeating the same fix for recurring issues
- Learns patterns (e.g., "this container crashes every Tuesday at 3 AM")
- Discord notifications for all actions taken (with deduplication)

### Key Design Decisions

- **No LLM for routine tasks** — uses rule-based logic for known patterns, only escalates to AI for complex unknowns
- **3-tier escalation** — fast/cheap model first, expensive model only when needed, Claude Code as final backstop
- **Failure memory prevents loops** — if a fix was tried and failed, it won't be retried until cooldown expires
- **Fingerprint-based deduplication** — same alert won't spam Discord; resolved alerts are sent when issues clear

---

## SearXNG (Self-Hosted Web Search)

A self-hosted metasearch engine running on LXC 200, port 8888. Aggregates results from multiple search engines without tracking.

### Integrations

| Consumer | How |
|----------|-----|
| **AI Agent** | Web search tool calls via JSON API |
| **Open WebUI** | Configured as search provider for AI-assisted browsing |
| **Homepage** | Search widget (replaces Google) |

### API

```bash
# JSON search
curl "http://YOUR_DOCKER_HOST_IP:8888/search?q=proxmox+gpu+passthrough&format=json"
```

---

## Paperless Tagging

The AI agent can manage Paperless documents via natural language:

| Endpoint | Purpose |
|----------|---------|
| `GET /api/documents/tags` | List all tags |
| `POST /api/documents/tags` | Create a new tag |
| `POST /api/documents/tag` | Tag a document by name |
| `POST /api/documents/correspondent` | Set document correspondent |
| `GET /api/documents/search?q=...` | Search documents |

Example: "Tag all my tax documents from 2025 with 'taxes'" — the agent searches Paperless, finds matching documents, and applies the tag.

---

## Gaming API

Endpoints at `/api/gaming/*` for game management:

| Endpoint | Purpose |
|----------|---------|
| `GET /api/gaming/search?q=...` | Search games via Gamarr |
| `POST /api/gaming/download` | Download ROMs or PC games |
| `GET /api/gaming/sync-status` | Check game-sync.sh status on Bazzite |
| `GET /api/gaming/bazzite-status` | Bazzite VM status (SSH, Sunshine/Moonlight) |
| `GET /api/gaming/stats` | Game collection stats by platform |

---

## Storage API

Per-node disk usage monitoring:

| Endpoint | Purpose |
|----------|---------|
| `GET /api/system/storage` | All nodes' disk usage |
| `GET /api/system/storage/{node}` | Specific node (used/free/total/percent) |
| `POST /api/system/backup/{target}` | Trigger backup for a specific target |

---

## Ollama Models (LXC 102)

| Model | Size on GPU | Speed | Purpose |
|-------|-------------|-------|---------|
| **qwen3.5:35b-a3b** | 34.5 GB (GTT) | ~22 ms/token | Chat, tool calling, Tier 2 smart fixer |
| **qwen3:1.7b** | 6.2 GB (GTT) | ~8 ms/token | Intent parsing, Tier 1 fast repairs |
| **nomic-embed-text** | 275 MB | — | Document RAG embeddings |

Both active models load entirely into GPU memory via GTT (61.7 GB available). The 2-minute idle timeout (`OLLAMA_KEEP_ALIVE=2m`) frees GPU memory when models are not in use.

### Open-WebUI

- ChatGPT-like web interface for Ollama
- Port 8080 (pip-installed, not Docker)
- Data stored at `/var/lib/open-webui/`
- **SearXNG integration** for AI-assisted web search
- **MCP tools** for Proxmox and homelab management
- Runs as a systemd service

### MCP Tools Proxy

Bridges Proxmox and homelab management tools into the chat interface:

```
Open-WebUI → mcpo proxy (port 8100 on AIServer host) → MCP servers → pvesh / homelab API
```

This lets you manage VMs/containers from the chat UI ("start VM 103", "show cluster status").

### Memory Gotcha

Large models (35B+) need significant free RAM. Ollama checks `MemFree`, not `MemAvailable`. If you get "model requires more system memory":

```bash
# Drop filesystem caches to free RAM
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
# Then restart Ollama
sudo systemctl restart ollama
```

---

## ML Research (LXC 105)

### GPU Passthrough (AMD)

The Radeon 8060S (Strix Halo, gfx1151) is passed through to this container via `/dev/dri` and `/dev/kfd`.

- **ROCm**: SDK 7.12 (nightly, for gfx1151 support)
- **PyTorch**: Nightly build with native gfx1151 kernels
- **No HSA override needed** — native support in nightly wheels

```bash
# Install PyTorch with ROCm for gfx1151
pip install torch --index-url https://rocm.nightlies.amd.com/v2/gfx1151/
```

### Stack

- Python 3.11 with full scientific stack (numpy, scipy, pandas, matplotlib, scikit-learn)
- PyTorch 2.9+ with ROCm 7.12
- Triton 3.5+ for kernel compilation
- 48 GB RAM, 32 vCPUs

---

## Nightly Tests (88 tests, 5 AM daily)

Comprehensive end-to-end test suite that validates every service in the homelab is functioning correctly.

- **Timer**: `nightly-tests.timer` / `nightly-tests.service`
- **Location**: `/home/admin/nightly-tests/run_all.sh`
- **Coverage**: HTTP health checks, API endpoints, SSH connectivity, Docker containers, Proxmox cluster, smart fixer validation, tiered escalation checks, 35b model responsiveness
- **Notification**: Results posted to Discord with pass/fail summary
- **Runtime**: ~60 seconds for all 88 tests
