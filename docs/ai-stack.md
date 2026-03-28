# AI / ML Stack

Multiple dedicated LXC containers on a 128 GB RAM node for running local LLMs, ML research, AI experiments, and AI-powered automation. The centerpiece is a **tool-calling AI agent** that controls the entire homelab via natural language.

---

## Architecture

```
AIServer (128 GB RAM, 32 cores, Ryzen AI MAX+ 395, Radeon 8060S iGPU)
│
├── LXC 102 — "openclaw" (28 GB — LLM Chat)
│   ├── Ollama (model serving, 2min idle timeout)
│   │   ├── qwen3.5:35b-a3b (23 GB, chat + tool calling)
│   │   ├── qwen3:1.7b (1.4 GB, Discord bot intent parsing)
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
├── LXC 100 — "media-monitor" (8 GB — Health Agent)
│   ├── Ollama qwen2.5:7b (local reasoning)
│   └── Automated health check + auto-fix + torrent recovery
│
├── Host services:
│   ├── Homelab API (port 9105) — unified FastAPI with AI agent (64+ tools)
│   │   ├── /api/ai/jarvis — tool-calling agent endpoint
│   │   ├── /api/guardian/* — proxies to Go Sentinel
│   │   ├── /api/verify/* — proxies to Go Sentinel library verification
│   │   ├── /api/diag/* — diagnostic tools
│   │   ├── /api/gaming/* — game search + download
│   │   └── /api/system/storage — per-node disk usage
│   ├── Homelab Agent (port 9106) — proactive autonomous monitoring
│   │   ├── Container doctor (14 containers, auto-restart)
│   │   ├── Source intelligence (13 Librarr sources, hourly)
│   │   ├── Import watchdog (stuck downloads, failed imports)
│   │   └── AI escalation (to /api/ai/jarvis for complex failures)
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

### GPU Note (AMD 8060S iGPU)
- Only **2 GB VRAM** — models don't fit, weights stay in system RAM
- GPU used for compute (matrix ops), not weight storage
- System RAM used for weights **counts against LXC memory limit**
- VRAM is separate and **bypasses** container limits
- Shared across LXCs 102, 105, 106 via /dev/dri + /dev/kfd
- Not exclusive like RTX 2070 on pve (fully owned by VM 103)

---

## AI Tool-Calling Agent

The `/api/ai/jarvis` endpoint is a full tool-calling agent — not just a chat wrapper. It uses Ollama's native tool calling with qwen3.5:35b-a3b to decide which actions to take, execute them, and synthesize results.

### Agent Loop

```
User message (any interface)
  └── Homelab API /api/ai/jarvis
        └── Build tool definitions (64+ tools)
              └── Send to Ollama with tool_call capability
                    └── LLM returns tool_call decisions
                          └── Execute tool calls against homelab APIs
                                └── Feed results back to LLM
                                      └── LLM generates final response
                                            (or makes more tool calls)
```

### Interfaces

The same agent brain powers three interfaces:

| Interface | Access | Notes |
|-----------|--------|-------|
| **Discord bot** | `*ai <anything>` in Discord | Sub-second intent parsing via qwen3:1.7b, then routes to agent |
| **Homepage chat widget** | Floating bubble on dashboard | Custom JS/CSS with tool-call progress indicators |
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

## Local LLM Chat (LXC 102)

### Ollama

- Serves large language models locally
- Current model: `qwen3.5:35b-a3b` (23 GB, Q4_K_M quantization)
- **Native tool calling** support — used by the AI agent
- API endpoint: `http://<lxc-ip>:11434`
- Runs as a systemd service (auto-start on boot)

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

---

## Media Monitor Agent (LXC 100)

An autonomous health monitoring agent that:

1. Runs periodic health checks on all Docker services (every 5 minutes)
2. Uses a small local LLM to reason about failures and suggest fixes
3. Executes safe remediation actions (restart containers, fix permissions)
4. Logs all actions to a SQLite audit database
5. Sends Discord notifications for significant events

### Architecture

```
systemd timer (5min)
  └── monitor.py
        ├── HTTP probes (all services)
        ├── Docker health checks (via SSH to LXC 200)
        ├── Rule-based pre-LLM fixes (known patterns)
        ├── LLM reasoning (for unknown failures)
        └── Action execution + audit log
```

### Optimizations

- Only sends failing checks to the LLM (not all 59 probes)
- `num_ctx=8192` for sufficient context
- Fallback summary mode if LLM is unavailable
- Rule-based fixes for known issues (e.g., dead network namespace -> restart gluetun)

---

## Homelab Agent (Proactive Autonomous Monitoring)

A proactive monitoring agent running on AIServer (port 9106) that scans the entire homelab every 15 minutes, detecting and fixing issues before they become visible to the user.

### Architecture

```
systemd service (continuous, 15min scan loop)
  └── agent.py
        ├── container_doctor — monitors 14 key containers, auto-restart, crash loop detection
        ├── source_intelligence — checks 13 Librarr search sources hourly, tracks availability
        ├── import_watchdog — stuck downloads, failed imports, auto-retry
        └── ai_escalation — complex failures → /api/ai/jarvis for AI-driven diagnosis
```

### Modules

| Module | Purpose | Frequency |
|--------|---------|-----------|
| **Container Doctor** | Monitors 14 key containers, auto-restarts crashed ones, crash loop guard | Every 15 min |
| **Source Intelligence** | Checks all 13 Librarr sources, tracks availability, detects outages | Every 60 min |
| **Import Watchdog** | Detects stuck downloads and failed imports, auto-retries | Every 15 min |
| **AI Escalation** | Escalates complex/recurring failures to AI agent for diagnosis | On failure |

### Failure Memory

- SQLite database tracks all failures and remediation attempts
- Prevents repeating the same fix for recurring issues
- Learns patterns (e.g., "this container crashes every Tuesday at 3 AM")
- Discord notifications for all actions taken

### Key Design Decisions

- **No LLM for routine tasks** — uses rule-based logic for known patterns, only escalates to AI for complex unknowns
- **Separate from media-monitor** — media-monitor (LXC 100) handles reactive health checks; homelab-agent handles proactive monitoring and source intelligence
- **Failure memory prevents loops** — if a fix was tried and failed, it won't be retried until cooldown expires

---

## Nightly Tests (45 tests, 5 AM daily)

Comprehensive end-to-end test suite that validates every service in the homelab is functioning correctly.

- **Timer**: `nightly-tests.timer` / `nightly-tests.service`
- **Location**: `/home/admin/nightly-tests/run_all.sh`
- **Coverage**: HTTP health checks, API endpoints, SSH connectivity, Docker containers, Proxmox cluster
- **Notification**: Results posted to Discord with pass/fail summary
- **Runtime**: ~48 seconds for all 45 tests
