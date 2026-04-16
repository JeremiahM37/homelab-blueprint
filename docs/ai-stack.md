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

## File Browser

A web-based file browser for accessing files across all LXC containers from any device on the network. Available on the Homepage dashboard under Tools.

| Endpoint | Purpose |
|----------|---------|
| `GET /api/diag/files/browse?lxc=105&path=/home` | List directory contents on any LXC |
| `POST /api/diag/files/prepare` | Prepare a file for download (copies to temp) |
| `GET /api/diag/files/serve/{file_id}` | Download a prepared file |
| `GET /api/diag/files/download?lxc=105&path=...` | Direct streaming download |

Supports LXCs 102 (OpenClaw), 104 (Work Env), 105 (Research), and 228 (AIServer host). Files are pulled from containers via `pct pull` and served to the browser.

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
| **qwen3.5:35b-a3b** | 34.5 GB (GTT) | ~22 ms/token | Eval-proven 10/10 — tool calling, Tier 2 smart fixer, eval harness agent + judge |
| **gemma4:e4b** | 9.6 GB (GTT) | ~12 ms/token | Production Jarvis default — faster, good for most chat |
| **qwen3:1.7b** | 6.2 GB (GTT) | ~8 ms/token | Tier 1 fast repairs, Discord file-intent detection |
| **nomic-embed-text** | 275 MB | — | Document RAG, episodic memory, tool-router embeddings |

Models load into GPU memory via GTT (61.7 GB available). `OLLAMA_MAX_LOADED_MODELS=1` means only one big model resident at a time — the eval harness deliberately runs agent + judge on the **same** model to avoid thrash. Idle timeout `OLLAMA_KEEP_ALIVE=2m` reclaims GPU memory between batches.

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

## LLM Observability (Traces)

Every Ollama call made by the homelab-api, the homelab-agent smart fixer, and the eval harness records a row in `traces.db` — an append-only SQLite store. Enables cost/latency analysis, model-vs-prompt A/B, and debugging stuck agent loops.

**Schema captures:** timestamp, caller (e.g. `jarvis.agent.r0`, `smart_fixer.r3`, `evals.judge`), model, latency_ms, prompt_tokens, completion_tokens, num_tool_calls, tool_names, tool_success, error, prompt_preview, response_preview.

**Never raises** — a failed insert is logged and swallowed so tracing can't take down the caller. Tracing writes from outside the API process (e.g. homelab-agent on the host) POST to `/api/traces/record`.

| Endpoint | Purpose |
|----------|---------|
| `GET /api/traces/recent?caller=&limit=` | Newest rows, optionally filtered by caller |
| `GET /api/traces/stats?hours=24` | Per-caller / per-model aggregates: calls, mean latency, errors, token totals |
| `GET /api/traces/errors?limit=` | Recent errored calls for debugging |
| `POST /api/traces/record` | Write endpoint for off-host callers (smart fixer, Discord bot) |

The mobile PWA's System tab surfaces this in real time: last-24h call count, error rate, avg latency, top-4 callers table.

---

## Episodic Memory

Chat conversations are summarized and embedded after each Jarvis turn-pair. On a new message, the top-3 most relevant prior summaries are retrieved via cosine similarity and injected into the system prompt — so the assistant remembers context across sessions and across interfaces (a preference stated on Discord is available in the PWA).

**Storage:** SQLite + in-memory cosine search, no extra dependencies. A few thousand 768-dim vectors search in under 10ms in pure Python — well below the latency floor of the Ollama call they accompany.

**Summarization:** `gemma4:e4b` with a 2-sentence third-person rubric that emphasizes retrieval keys (names, numbers, services) over prose.

**Privacy:** PWA exposes a "Memory" modal (episodic tab) that lists recent episodes with a per-row "forget" button. Deleted summaries are wiped from both the row table and the embedding vector.

| Endpoint | Purpose |
|----------|---------|
| `POST /api/episodic/store` | External clients (e.g. Discord) push a turn-pair for summarization |
| `GET /api/episodic/retrieve?q=&top_k=&channel=` | Retrieve top-k relevant summaries for a query |
| `GET /api/episodic/recent?limit=&channel=` | Most-recent-first list (no retrieval) |
| `GET /api/episodic/stats` | Total episodes, per-channel counts, oldest/newest timestamps |
| `DELETE /api/episodic/episode/{id}` | Forget a single episode |

---

## Unified Homelab RAG

Extends `doc-rag` (Paperless-only previously) with a second Chroma collection (`homelab_unified`) that ingests Sonarr/Radarr/Jellyfin/homelab-agent-failures/git-commits. Each document carries a `source` metadata tag so queries can be filtered — "what movies do I have" with `?source=radarr` only returns movie data.

**Ingest:** Nightly at 04:30 via systemd timer (`homelab-reindex.timer`). Each source is fetched independently so a single broken API can't take down the whole index. Fetchers are isolated — one raising an exception doesn't affect the others.

**Sources:**
- **Sonarr**: all series with monitored state + episodes-missing count
- **Radarr**: all movies with has-file/monitored state
- **Jellyfin**: library items (movies/shows/audiobooks) with overview + genres
- **Agent failures**: SQLite rows from homelab-agent's failure memory
- **Git commits**: last 200 commits across `librarr-go`, `homelab-agent`, `homelab-api`, `doc-rag`

| Endpoint | Purpose |
|----------|---------|
| `GET /api/homelab/ask?q=&source=` | RAG answer, optionally filtered by source |
| `GET /api/homelab/search?q=&source=` | Raw vector-similarity results |
| `POST /api/homelab/reindex` | Full rebuild (pull + embed all sources) |
| `GET /api/homelab/status` | Indexed chunk count, per-source counts, last sync timestamp |

Example: `/api/homelab/ask?q=what+movies+do+I+have&source=radarr` returns a real answer backed by actual Radarr inventory.

---

## Code Execution Sandbox

The AI agent can execute Python/bash in a hardened bubblewrap sandbox — useful for ad-hoc computation, parsing text the user pasted, math, format conversions, regex checks, any quick transformation the built-in tools don't cover.

**Isolation (defense in depth):**
- `--unshare-all` plus explicit `--unshare-net` — new user/mount/pid/ipc/uts/cgroup/net namespaces
- Read-only bind of a whitelisted set of system dirs (`/usr /lib /bin /sbin /etc/alternatives /etc/ssl/certs`)
- Writable `/sandbox` via tmpfs, destroyed per-run
- `prlimit` caps: 20s CPU, 512MB address space, 50MB file size, 128 file descriptors, 32 processes
- Wall-clock timeout with `SIGKILL` on overrun (default 5s, max 30s)
- Output truncation at 256KB/stream, code size capped at 128KB
- `--die-with-parent` — a crashed homelab-api cannot leave orphan sandboxes

**Agent tool:** `execute_code({"code": "...", "timeout": 5})` — listed in the agent's tool catalog. Semantic routing surfaces it for prompts mentioning "calculate", "compute", "parse", "python", etc. Results (stdout/stderr/exit code/runtime) are rendered inline in the PWA's chat as a collapsible code block.

| Endpoint | Purpose |
|----------|---------|
| `POST /api/sandbox/python` | Run a Python snippet |
| `POST /api/sandbox/bash` | Run a bash script |
| `GET /api/sandbox/info` | Engine config + hardening status |

**Security tests run in CI and nightly:** network escape attempts, SSH-keys-invisible, `/etc/shadow`-unreadable, write-outside-sandbox blocked, fork-bomb contained, memory limit enforced, timeout kills runaway loops. A failing **"sandbox network isolation BROKEN"** check in the nightly is a hard quarantine signal.

---

## Tier 2 Fix Verify Step

After the Tier 2 smart fixer declares a fix applied, `fix_verify` independently checks whether the fix actually worked. On failure, the file edits are reverted from their pre-edit backups and `fix_applied` is downgraded so the issue escalates to Tier 3 instead of being trusted.

**Checks:**
1. **Syntax validation** on every edited file — `compile()` for `.py`, `json.loads` for `.json`, `yaml.safe_load` for `.yaml/.yml`. Unknown extensions pass by default (no false fails for files we can't easily validate).
2. **Container health** for any containers the fixer rebuilt or restarted — `docker inspect -f '{{.State.Status}}|{{.State.Health.Status}}'` in a polling loop up to 45s. Must reach `running` (and `healthy` if a healthcheck is configured).
3. **LLM judge** (optional, `gemma4:e4b` with `format: json`) — scores 0.0-1.0 on whether the agent's actions plausibly address the original issue. Threshold default 0.4.

**Revert:** Uses the existing `smart_fixer` backup directory (`/home/admin/homelab-agent/backups/`). Finds the newest backup matching the basename, restores it, and reports the reverted paths in the result dict.

Verified by 22 unit tests covering all-green, syntax-failure, container-unhealthy, low-judge-score, no-fix-applied, and judge-disabled paths.

---

## Semantic Tool Routing

The old `_select_tools` used keyword matching — it required the literal word "verify" in a message to offer verify tools. "Is Batman in jellyfin? **prove it**" wouldn't match. Semantic routing fixes this by embedding tool descriptions once and cosine-similarity matching against the embedded user message.

**Hybrid strategy (kept ≥ what keyword routing caught):**
- Keyword hits = baseline (deterministic, preserves every previous behavior)
- Union with top-5 semantic matches above a 0.58 cosine floor
- Total capped at 14 tools — empirically, small models get confused by 18+

**Cache:** Embeddings pickled to disk (`tool_embeddings.pkl`), keyed by tool name + description hash. Descriptions are auto-re-embedded when changed. Startup hook in `main.py` warms the cache in a background thread so uvicorn boot isn't blocked if Ollama is cold.

**Fallback:** If the embedder is unreachable at request time, routing silently falls back to pure keyword. If the cache is empty at request time, returns all tools (over-inclusive > empty).

| Endpoint | Purpose |
|----------|---------|
| `GET /api/ai/tools/select?q=...` | Debug endpoint — shows which tools got picked and why (full ranking) |
| `POST /api/ai/tools/warm-up` | Force re-embed after editing any tool description |

The PWA's AI tab has a "🛠 Tools" button that opens this endpoint interactively — type a query, see the ranked tool list with scores and checkmarks for which were selected.

---

## Eval Harness

Regression protection for AI changes. A canned set of prompts replays nightly against the Jarvis agent; each response is scored 0-1 by a judge model against written criteria. Results go to SQLite so the whole history is comparable.

**Prompt format** (`evals/prompts.jsonl`, 10 prompts):
```json
{"id": "library-search",
 "prompt": "do I have inception in my library?",
 "expect_tools": ["search_library", "verify_in_library"],
 "judge": "Response must give a definitive yes/no..."}
```

**What the harness revealed (and we fixed):**
- Baseline keyword routing: 4/10 passing, mean 0.40
- Semantic routing (uncapped): 4/10 — too many tools confused the model
- Semantic routing (capped at 14): 5-6/10, mean 0.55
- Stronger system prompt + hallucination-phrase detector: 7/10, mean 0.83
- Plaintext-leak detector (`CALL list_torrents{}` → real tool_call): 9/10, mean 0.90
- qwen3.5:35b-a3b agent + same-model judge + 3-attempt retry: **10/10, mean 1.00**, stable across 5 consecutive runs

**Nightly** at 06:00 via `evals-nightly.timer`. The nightly shell checks include a regression gate (`mean >= 0.80`) — if the agent regresses, the nightly fails loudly on Discord.

| Endpoint | Purpose |
|----------|---------|
| `POST /api/evals/run` | Run the full suite. Body: `{"run_id": ..., "model": "qwen3.5:35b-a3b"}` |
| `GET /api/evals/latest` | Most recent run's per-prompt breakdown + mean |
| `GET /api/evals/history?prompt_id=&limit=` | Per-prompt history for tracking regressions |
| `GET /api/evals/trend?days=30` | Per-run aggregates over time — sparkline-ready |
| `GET /api/evals/prompts` | Show the configured prompt set |

The PWA's System tab renders a sparkline of the last 14 runs' mean scores.

---

## Morning Briefing

Daily 08:00 Discord push summarizing overnight state. Seven sections: system health, storage (with warnings above 85%), downloads (arrived / in-flight / failed from Sentinel), recent books, agent activity (deduplicated), AI stack status (calls / error rate / latency / eval score / memory count), and errors.

Color-coded embed:
- Red: many errors OR eval score < 0.7
- Amber: any errors
- Blue: all green

Link buttons deep-link to relevant PWA tabs (System, AI Chat, Books, Feed) so drill-down is one tap away. Interactive action buttons (e.g. "restart qbit") are deferred — they require a persistent bot listener and are a separate design.

**Scheduled:** `/etc/systemd/system/morning-briefing.timer` → `morning_briefing.py` → Discord channel.

---

## Mobile PWA (AI surface extensions)

`http://<AISERVER_IP>:9105/app` is the full daily dashboard. AI-specific extensions:

| Tab / Feature | What it shows |
|---------------|---------------|
| **System → AI — last 24h** | LLM call count, error rate, avg latency, token total, top-4 callers table |
| **System → Eval sparkline** | Last-14-run mean score trend, color-coded |
| **AI → 🧠 Memory** | Modal listing episodes with a per-row "forget" button |
| **AI → 🛠 Tools** | Modal showing semantic routing on-the-fly — type a query, see which tools would be offered and at what similarity score |
| **AI chat code blocks** | `execute_code` tool results render as collapsible panels showing the Python source, stdout, stderr, exit code |

---

## Nightly Tests (88 tests, 5 AM daily)

Comprehensive end-to-end test suite that validates every service in the homelab is functioning correctly.

- **Timer**: `nightly-tests.timer` / `nightly-tests.service`
- **Location**: `/home/admin/nightly-tests/run_all.sh`
- **Coverage**: HTTP health checks, API endpoints, SSH connectivity, Docker containers, Proxmox cluster, smart fixer validation, tiered escalation checks, 35b model responsiveness
- **Notification**: Results posted to Discord with pass/fail summary
- **Runtime**: ~60 seconds for all 88 tests
