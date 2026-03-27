# Monitoring & Automation

Multiple layers of monitoring ensure services stay healthy with minimal manual intervention.

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

┌────────────────┐  ┌──────────────┐  ┌───────────────┐
│  Uptime Kuma   │  │    n8n       │  │ Media Monitor │
│ (HTTP/TCP/ping │  │ (workflow    │  │ (LLM-assisted │
│  checks)       │  │  automation) │  │  health agent)│
└────────────────┘  └──────────────┘  └───────────────┘

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

## Media Monitor Agent

An autonomous agent on a dedicated LXC that combines traditional health checks with LLM-assisted reasoning.

### How It Works

1. **Probe phase**: HTTP checks against all services, Docker container status checks
2. **Rule-based fixes**: Known failure patterns are handled immediately without LLM
   - Dead network namespace -> restart gluetun + dependent containers
   - Permission errors -> `chown 1000:1000` on affected directories
3. **LLM reasoning**: Unknown failures are sent to a local LLM for analysis
   - Only failing checks are sent (not all 59 probes)
   - LLM suggests remediation actions
4. **Execution**: Safe actions are auto-executed; risky ones are logged for review
5. **Audit**: All actions logged to SQLite database
6. **Notification**: Discord webhook for significant events (both servers)

### Configuration

```json
{
  "check_interval": 300,
  "services": ["jellyfin", "sonarr", "radarr", "..."],
  "discord_webhook": "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN",
  "llm_endpoint": "http://localhost:11434",
  "llm_model": "qwen2.5:7b"
}
```

---

## Homepage Dashboard

### Sections

| Section | Contents |
|---------|----------|
| **Server Temps** | AIServer, pve, MediaServer CPU/GPU/NVMe temps (via temp APIs on port 9101) |
| **Backups** | Docker Configs, AIServer, Gaming Server backup status (via backup-status-api on port 9102) |
| **Disk Usage** | Per-device storage widgets (AIServer, DAS, pve, LXC 200) |
| **Infrastructure** | Homelab API, Terraform, Open WebUI, SearXNG links |
| **Media/Books/Games** | All service widgets with stats |

### AI Chat Widget

A floating chat bubble (implemented via `custom.js` and `custom.css`) that connects to the AI agent:

- Sends messages to `/api/ai/jarvis`
- Shows **tool-call progress indicators** as the agent works
- Supports the full 40+ tool set from the dashboard

### Search Widget

The Homepage search bar uses **SearXNG** (self-hosted) instead of Google:

```yaml
# homepage search widget config
search:
  provider: custom
  url: http://YOUR_DOCKER_HOST_IP:8888/search?q=
```

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
- **node-exporter**: Host CPU, memory, disk, network

### CrowdSec

- Intrusion detection analyzing container logs
- Community-driven threat intelligence
- Can ban IPs via bouncers (e.g., Cloudflare bouncer for tunnel traffic)
