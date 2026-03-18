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
```

---

## Uptime Kuma

Simple uptime monitoring for all services. Checks HTTP endpoints, TCP ports, and ping targets. Sends alerts when services go down.

- Port: 3001
- Monitors all 35+ Docker services + external endpoints

---

## n8n Watchdog Workflows

Automated workflows that detect and remediate common failures.

### Bazzite VM Watchdog

- **Trigger**: Every 5 minutes
- **Action**: Pings the gaming VM's Tailscale IP from the Proxmox host
- **Remediation**: If the VM is unresponsive (frozen), automatically resets it via Proxmox API (`pvesh`)
- **Why**: GPU passthrough VMs occasionally freeze, and the host has no display (GPU is passed through) so manual intervention requires SSH

### Container Watchdog

- **Trigger**: Every 2 minutes
- **Action**: Checks qBittorrent and gluetun health
- **Logic**:
  - HTTP 403 from qBit = running (just needs auth) → healthy
  - ECONNREFUSED/ETIMEDOUT = crashed → restart
  - Any HTTP response from gluetun = VPN working
  - Network error from gluetun = VPN down → restart
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

## Media Monitor Agent

An autonomous agent on a dedicated LXC that combines traditional health checks with LLM-assisted reasoning.

### How It Works

1. **Probe phase**: HTTP checks against all services, Docker container status checks
2. **Rule-based fixes**: Known failure patterns are handled immediately without LLM
   - Dead network namespace → restart gluetun + dependent containers
   - Permission errors → `chown 1000:1000` on affected directories
3. **LLM reasoning**: Unknown failures are sent to a local LLM for analysis
   - Only failing checks are sent (not all 59 probes)
   - LLM suggests remediation actions
4. **Execution**: Safe actions are auto-executed; risky ones are logged for review
5. **Audit**: All actions logged to SQLite database
6. **Notification**: Discord webhook for significant events

### Configuration

```json
{
  "check_interval": 300,
  "services": ["jellyfin", "sonarr", "radarr", "..."],
  "discord_webhook": "https://discord.com/api/webhooks/...",
  "llm_endpoint": "http://localhost:11434",
  "llm_model": "qwen2.5:7b"
}
```

---

## n8n Tips & Gotchas

- **Version**: n8n v2.x Code nodes do NOT support `fetch()` — use HTTP Request nodes instead
- **Docker access**: Use docker-socket-proxy (TCP 2375) since there's no `executeCommand` node
- **Fan-out pattern**: Trigger → multiple parallel nodes → merge causes timing errors. Use sequential chains instead.
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
