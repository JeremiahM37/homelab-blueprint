# Monitoring & Automation

Multiple layers of monitoring ensure services stay healthy with minimal manual intervention. The **Homelab Agent** provides proactive autonomous monitoring with a 3-tier AI repair system, while n8n workflows handle specific watchdog tasks.

---

## Monitoring Stack

```
┌─────────────────────────────────────────────────────┐
│                   Grafana (dashboards)               │
│                        ▲                             │
│            ┌───────────┼───────────┐                 │
│            │           │           │                 │
│        Prometheus   cAdvisor   node-exporter         │
│       (time-series) (container) (host metrics)       │
└─────────────────────────────────────────────────────┘

┌────────────────┐  ┌──────────────┐  ┌───────────────────────┐
│  Uptime Kuma   │  │    n8n       │  │   Homelab Agent       │
│ (HTTP/TCP/ping │  │ (workflow    │  │ (7-module proactive   │
│  checks)       │  │  automation) │  │  monitoring + 3-tier  │
└────────────────┘  └──────────────┘  │  AI repair system)    │
                                      └───────────────────────┘

┌─────────────────────────────────────────────────────┐
│               Library Verification                   │
│  Real API proof — file paths, durations, page counts │
│  /api/verify/check  ·  /api/verify/check-all         │
└─────────────────────────────────────────────────────┘
```

---

## Uptime Kuma

Simple uptime monitoring for all services. Checks HTTP endpoints, TCP ports, and ping targets. Sends alerts when services go down.

- Port: 3001
- Monitors all 35+ Docker services + external endpoints

---

## Homelab Agent (Proactive Autonomous Monitoring)

The primary monitoring system. Runs on AIServer (port 9106) and scans the entire homelab every 5 minutes, detecting and fixing issues before they become visible to the user. Replaced the earlier Media Monitor (LXC 100), consolidating all monitoring into a single agent on the host.

### 7 Modules

| Module | Purpose | Frequency |
|--------|---------|-----------|
| **Container Doctor** | Monitors 14 key containers, auto-restarts crashed ones, crash loop guard | Every 5 min |
| **Source Intelligence** | Checks all 13 Librarr search sources, tracks availability, detects outages | Every 60 min |
| **Import Watchdog** | Detects stuck downloads and failed imports, auto-retries | Every 5 min |
| **Torrent Doctor** | qBit health checks, VPN stall detection, orphan routing, dead torrent replacement via Prowlarr, ratio-limit checks | Every 5 min |
| **System Monitor** | DAS mount verification, disk space with 7-day forecasting, host load/RAM, container resource outliers, Prowlarr indexer auto-retry, Tdarr/Unpackerr/Cloudflared monitoring, n8n workflow checks, download directory permissions | Every 5 min |
| **Notifications** | Fingerprint-based alert deduplication, resolved notifications, rate limiting, weekly digest | Continuous |
| **AI Escalation** | 3-tier repair system — Tier 1 (1.7b fast tools) → Tier 2 (35b smart fixer) → Tier 3 (Claude Code) | On failure |

### 3-Tier AI Repair System

When the agent detects an issue, it escalates through three tiers:

```
Issue detected
  │
  ├── Tier 1: qwen3:1.7b (instant, tool calls via Jarvis API)
  │     Handles ~90% of issues in <1 second
  │     Tools: restart, permissions, rescan, search, download
  │     ├── Fixed? → log + notify → done
  │     └── Failed? → escalate
  │
  ├── Tier 2: qwen3.5:35b-a3b (think: true, 19 tools)
  │     Smart fixer with file editing, command execution, container rebuilds
  │     Backs up files before editing, logs everything to audit_log.md
  │     ├── Fixed? → log + notify → done
  │     └── Failed? → write fix-request.md → escalate
  │
  └── Tier 3: Claude Code (runs every 5 hours)
        Reviews audit_log.md, reverts bad Tier 2 changes
        Picks up fix-request.md for issues Tiers 1+2 couldn't solve
```

### Failure Memory

- SQLite database tracks all failures and remediation attempts
- Prevents repeating the same fix for recurring issues
- Fingerprint-based alert deduplication — same alert won't spam Discord
- Resolved notifications sent when issues clear

---

## n8n Watchdog Workflows

Automated workflows that detect and remediate common failures. All workflows send alerts to **both Discord servers** (dual-channel).

### Bazzite VM Watchdog

- **Trigger**: Every 5 minutes
- **Action**: Pings the gaming VM's Tailscale IP from the Proxmox host
- **Remediation**: If the VM is unresponsive (frozen), automatically resets it via Proxmox API (`pvesh`)
- **Why**: GPU passthrough VMs occasionally freeze, and the host has no display (GPU is passed through) so manual intervention requires SSH

### Container Watchdog

- **Trigger**: Every 2 minutes
- **Action**: Checks qBittorrent and gluetun health
- **Logic**:
  - HTTP 403 from qBit = running (just needs auth) -> healthy
  - ECONNREFUSED/ETIMEDOUT = crashed -> restart
  - Any HTTP response from gluetun = VPN working
  - Network error from gluetun = VPN down -> restart
- **Remediation**: Restarts crashed containers via docker-socket-proxy

### Prowlarr Health Check

- Monitors Prowlarr indexer status via API
- Alerts on failed indexers

### Arr App Health Check

- Monitors Sonarr, Radarr, Bazarr health endpoints
- Alerts on import failures, disk space issues

### VPN Leak Detection

- Verifies gluetun VPN tunnel is active
- Checks public IP matches expected VPN exit

### Disk Space Monitor

- SSH into the media server to check disk usage
- Alerts when DAS or root filesystem gets low

---

## Storage Monitoring

### Per-Node Disk Usage API

The unified API provides real-time disk usage for every node:

```bash
# All nodes at once
curl http://YOUR_AISERVER_IP:9105/api/system/storage

# Specific node
curl http://YOUR_AISERVER_IP:9105/api/system/storage/aiserver
```

Returns used/free/total/percent for each filesystem.

### Homepage Disk Usage Widgets

The Homepage dashboard includes a **Disk Usage** section with per-device storage widgets:

| Widget | What It Shows |
|--------|--------------|
| AIServer | Root filesystem usage |
| DAS (8TB) | Media storage usage |
| pve | Gaming node disk usage |
| LXC 200 | Docker host disk usage |

---

## Library Verification

The `/api/verify/*` endpoints perform **definitive** verification of library contents — real API calls that return proof, not fuzzy title matching.

### What Gets Checked

| Library | Verification Method |
|---------|-------------------|
| **Jellyfin** | Items API -> file path + media sources + runtime |
| **Audiobookshelf** | isMissing=false + numAudioFiles > 0 + duration |
| **Kavita** | Series pages > 0 + folder path |
| **Gamarr** | Download status + file existence |

### Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /api/verify/check?title=...&library=jellyfin` | Check specific library |
| `GET /api/verify/check-all?title=...` | Check ALL libraries simultaneously |

### Integration with Download Guardian

The Guardian's library verification loop uses these endpoints to confirm downloads actually landed in the correct library. It polls every 60 seconds for up to 30 minutes after a download completes.

---

## Homepage Dashboard

### Sections

| Section | Contents |
|---------|----------|
| **Server Temps** | AIServer, pve, MediaServer CPU/GPU/NVMe temps (via temp APIs on port 9101) |
| **Backups** | Docker Configs, AIServer, Gaming Server backup status (via backup-status-api on port 9102) |
| **Disk Usage** | Per-device storage widgets (AIServer, DAS, pve, LXC 200) |
| **Infrastructure** | Homelab API, Homelab Agent, Terraform, Open WebUI, SearXNG links |
| **Media/Books/Games** | All service widgets with stats |

### AI Chat Widget

A floating chat bubble (implemented via `custom.js` and `custom.css`) that connects to the AI agent:

- Sends messages to `/api/ai/jarvis`
- Shows **tool-call progress indicators** as the agent works
- Supports the full 64+ tool set from the dashboard

### Search Widget

The Homepage search bar uses **SearXNG** (self-hosted) instead of Google:

```yaml
# homepage search widget config
search:
  provider: custom
  url: http://YOUR_DOCKER_HOST_IP:8888/search?q=
```

---

## Nightly Tests (76 tests, 5 AM daily)

Comprehensive end-to-end test suite that validates every service in the homelab is functioning correctly.

- **Timer**: `nightly-tests.timer` / `nightly-tests.service`
- **Location**: `/home/admin/nightly-tests/run_all.sh`
- **Coverage**: HTTP health checks, API endpoints, SSH connectivity, Docker containers, Proxmox cluster, smart fixer validation, tiered escalation checks, 35b model responsiveness
- **Notification**: Results posted to Discord via Python JSON builder (avoids newline escaping issues with bash)
- **Runtime**: ~60 seconds for all 76 tests

---

## n8n Tips & Gotchas

- **Version**: n8n v2.x Code nodes do NOT support `fetch()` — use HTTP Request nodes instead
- **Docker access**: Use docker-socket-proxy (TCP 2375) since there's no `executeCommand` node
- **Fan-out pattern**: Trigger -> multiple parallel nodes -> merge causes timing errors. Use sequential chains instead.
- **Gluetun API**: Response body may be in `.data` as a string (content-type mismatch). Check both `.data.includes('public_ip')` and `.public_ip`.
- **SSH credentials**: Private key must be in credential data, not just node parameters. Host/port/username go in both.

---

## Metrics & Dashboards

### Prometheus + Grafana

- **Prometheus**: Scrapes metrics from cAdvisor (container metrics) and node-exporter (host metrics)
- **Grafana**: Dashboards for container resource usage, host performance, network traffic
- **cAdvisor**: Per-container CPU, memory, network, disk I/O
  - Optimized config: `housekeeping_interval=300s`, CPU capped at 0.10, memory limit 512 MB
  - Default cAdvisor settings caused excessive CPU load — tune `--docker_only=true` and disable expensive metrics (process, percpu, sched, memory_numa)
- **node-exporter**: Host CPU, memory, disk, network

### CrowdSec

- Intrusion detection analyzing container logs
- Community-driven threat intelligence
- Can ban IPs via bouncers (e.g., Cloudflare bouncer for tunnel traffic)
