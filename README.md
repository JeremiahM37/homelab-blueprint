# Homelab Blueprint

A three-node Proxmox cluster running media automation, gaming (with GPU passthrough + game streaming), AI/ML workloads, and self-hosted productivity tools — all on consumer hardware.

This repo documents the architecture, services, and lessons learned. No credentials or personal info — just the blueprint.

---

## Cluster Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Proxmox VE Cluster ("HomeServer")                       │
│                        3 nodes · PVE 9.1.1                                  │
├──────────────────┬──────────────────────┬───────────────────────────────────┤
│    Node: pve     │  Node: MediaServer   │     Node: AIServer                │
│  (Gaming/Dev)    │  (Media Stack Host)  │   (AI/ML Workloads)               │
│                  │                      │                                   │
│  CPU: i7-9700K   │  CPU: Ryzen 7 8845HS │  CPU: Ryzen AI MAX+ 395          │
│  RAM: 32 GB      │  RAM: 28 GB          │  RAM: 128 GB                     │
│  GPU: RTX 2070*  │  iGPU: Radeon 780M   │  iGPU: Radeon 8060S              │
│                  │                      │                                   │
│  ┌────────────┐  │  ┌────────────────┐  │  ┌───────────────────────────┐   │
│  │ VM 103     │  │  │ LXC 200        │  │  │ LXC 100  Media Monitor   │   │
│  │ Bazzite    │  │  │ Docker Host    │  │  │ LXC 101  Dev Workspace   │   │
│  │ Gaming VM  │  │  │ 35+ containers │  │  │ LXC 102  Ollama + WebUI  │   │
│  │ 4c/24GB    │  │  │ 12c/24GB       │  │  │ LXC 104  Work Env        │   │
│  │ GPU pass-  │  │  │                │  │  │ LXC 105  ML Research     │   │
│  │ through    │  │  │ + SearXNG      │  │  │ LXC 106  AI Detection    │   │
│  └────────────┘  │  └────────────────┘  │  ├───────────────────────────┤   │
│                  │                      │  │ Homelab API   :9105       │   │
│  * Only GPU in   │  DAS: 8TB btrfs      │  │  └─ AI Agent (Jarvis)    │   │
│    system —      │  (USB TerraMaster)   │  │  └─ Download Guardian    │   │
│    host goes     │                      │  │  └─ Library Verification │   │
│    headless      │                      │  │  └─ Diagnostic Tools     │   │
│    when VM runs  │                      │  │ Doc RAG         :9103    │   │
│                  │                      │  │ Terraform       :9104    │   │
│                  │                      │  └───────────────────────────┘   │
├──────────────────┴──────────────────────┴───────────────────────────────────┤
│                                                                             │
│   ┌── AI Agent Brain ──────────────────────────────────────────────────┐    │
│   │  qwen3.5:35b-a3b on Ollama (native tool calling, 48 tools)       │    │
│   │                                                                    │    │
│   │  Interfaces:                                                       │    │
│   │    Discord bot (*ai) ──┐                                           │    │
│   │    Homepage chat ──────┼── /api/ai/jarvis ── tool loop ── execute  │    │
│   │    Open WebUI (MCP) ──┘                                           │    │
│   │                                                                    │    │
│   │  Subsystems:                                                       │    │
│   │    Librarr (Go, 13 sources, Torznab/Newznab, OPDS, embedded UI)  │    │
│   │    Sentinel (Go, download guardian, library verification)         │    │
│   │    Diagnostics (file ops, log reading, library rescans)           │    │
│   │    SearXNG (self-hosted web search) ─── Open WebUI + Homepage     │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Hardware

| Node | CPU | Cores/Threads | RAM | GPU | Role |
|------|-----|---------------|-----|-----|------|
| **pve** | Intel i7-9700K | 8c/8t | 32 GB | NVIDIA RTX 2070 (passthrough) | Gaming / dev |
| **MediaServer** | AMD Ryzen 7 8845HS | 8c/16t | 28 GB | AMD Radeon 780M (iGPU) | Media stack |
| **AIServer** | AMD Ryzen AI MAX+ 395 | 16c/32t | 128 GB | AMD Radeon 8060S (iGPU) | AI/ML workloads |

### Storage

- **Boot drives**: Local LVM-thin on each node (~100 GB each)
- **DAS**: TerraMaster TDAS enclosure, USB-attached to MediaServer, 8 TB btrfs
  - Mounted at `/mnt/storage` on the MediaServer host
  - Bind-mounted into LXC 200 at `/data/media`
  - All media services depend on this mount — they won't start if the DAS is disconnected

---

## Network Topology

```
Internet
  │
  ├── Cloudflare Tunnel (cloudflared container)
  │     └── Reverse proxy to select services
  │
  ├── Tailscale mesh (node-to-node, stable IPs)
  │
  └── LAN (flat /24 network)
        │
        ├── pve node
        │     └── VM 103 (Bazzite) — bridged LAN + Tailscale
        │
        ├── MediaServer node
        │     └── LXC 200 — bridged LAN
        │           ├── gluetun VPN (Mullvad WireGuard)
        │           │     ├── qBittorrent
        │           │     ├── Librarr
        │           │     └── Gamarr
        │           └── SearXNG (self-hosted web search)
        │
        └── AIServer node
              ├── LXC 100-106 — bridged LAN
              ├── Homelab API + AI Agent (port 9105)
              └── MCP server (Proxmox management)
```

### VPN Architecture

Download clients (qBittorrent, Librarr, Gamarr) route through a **gluetun** container running Mullvad WireGuard. Services that need VPN protection use `network_mode: "service:gluetun"` in Docker Compose and expose their ports through gluetun.

---

## AI Assistant

The homelab is controlled by a **tool-calling AI agent** powered by a local 35B-parameter LLM (qwen3.5:35b-a3b) running on Ollama with native tool calling. The agent has **48 tools** for managing every aspect of the homelab, including Librarr search/download and Sentinel guardian/verification.

### How It Works

```
User (Discord / Homepage / Open WebUI)
  └── /api/ai/jarvis
        └── LLM decides which tools to call
              └── Executes against homelab APIs
                    └── Feeds results back to LLM
                          └── Generates natural language response
```

### Interfaces

All three interfaces share the same agent brain:

| Interface | How | Use Case |
|-----------|-----|----------|
| **Discord bot** | `*ai <anything>` command | Mobile / quick commands |
| **Homepage widget** | Floating chat bubble (custom.js) | Dashboard integration |
| **Open WebUI** | MCP tools proxy | Full chat UI with history |

### Key Subsystems

| System | Purpose |
|--------|---------|
| **Librarr** | Go binary (17 MB), 13 search sources, Torznab/Newznab API, OPDS feed, embedded web UI |
| **Sentinel** | Go binary (11 MB), download guardian with persistent job tracking, definitive library verification |
| **Diagnostic Tools** | File ops, log reading, permission fixes, library rescans — for AI escalation |
| **SearXNG** | Self-hosted web search for AI and dashboard |
| **Paperless Tagging** | AI-driven document tagging and correspondent assignment |
| **Gaming API** | Game search, ROM download, sync status, Bazzite VM control |

See [AI Stack](docs/ai-stack.md) for full details.

---

## Guests (VMs & Containers)

| VMID | Name | Node | Type | Resources | Purpose |
|------|------|------|------|-----------|---------|
| 100 | media-monitor | AIServer | LXC | 4c / 8 GB | AI self-healing health agent |
| 101 | project-env | AIServer | LXC | 4c / 4 GB | Development workspace |
| 102 | openclaw | AIServer | LXC | 16c / 28 GB | Local LLM chat (Ollama + Open-WebUI) |
| 103 | gaming-bazzite | pve | VM | 7c / 24 GB | Gaming VM with GPU passthrough |
| 104 | work-env | AIServer | LXC | 4c / 4 GB | Claude Code, Docker, dev tools |
| 105 | research-env | AIServer | LXC | 16c / 16 GB | AI/ML research with GPU passthrough |
| 106 | ai-detector | AIServer | LXC | 8c / 12 GB | AI text detection research |
| 200 | docker-server | MediaServer | LXC | 12c / 24 GB | Main Docker host (55+ containers) |

---

## Documentation

| Doc | Description |
|-----|-------------|
| [Docker Services](docs/docker-services.md) | All 55+ containers running on LXC 200 |
| [Gaming VM](docs/gaming-vm.md) | Bazzite setup, GPU passthrough, Sunshine/Moonlight streaming |
| [Game Pipeline](docs/game-pipeline.md) | Automated game download → install → Steam library pipeline |
| [AI Stack](docs/ai-stack.md) | Tool-calling agent, Download Guardian, verification, diagnostics, RAG, SearXNG |
| [Automation](docs/automation.md) | Download Guardian, backups, CrowdSec, Terraform, dual-channel alerts |
| [Monitoring](docs/monitoring.md) | n8n watchdog workflows, media-monitor agent, Homepage dashboard, storage monitoring |
| [Media Stack](docs/media-stack.md) | Jellyfin, *arr apps, download automation |
| [Networking](docs/networking.md) | VPN, Cloudflare tunnel, Tailscale mesh |
| [Lessons Learned](docs/lessons-learned.md) | Gotchas, debugging tips, things that broke |
| [Docker Compose (example)](docker-compose.example.yml) | Sanitized compose file |

---

## Quick Stats

- **8 guests** across 3 nodes (7 LXC + 1 VM)
- **55+ Docker containers** on a single LXC
- **~188 GB total RAM** across the cluster
- **8 TB DAS** for media storage
- **GPU passthrough** on 2 nodes (NVIDIA for gaming, AMD iGPU shared across 3 LXCs for ML)
- **AI tool-calling agent** — 48 tools, local 35B LLM, controls the entire homelab via natural language
- **3 agent interfaces** — Discord bot, Homepage chat widget, Open WebUI (same brain, same tools)
- **Librarr (Go rewrite)** — 17 MB binary, 13 search sources, Torznab/Newznab API, OPDS feed, embedded web UI
- **Sentinel (Go)** — download guardian with persistent job tracking, definitive library verification with proof
- **Diagnostic toolkit** — file ops, log reading, permission fixes, library rescans for AI escalation
- **SearXNG** — self-hosted web search for AI agent and Homepage dashboard
- **Unified API** — single FastAPI endpoint aggregating all services (Swagger docs included)
- **Document RAG** — vector search over 169+ documents via local embeddings + LLM
- **Automated backups** — Restic to DAS, 3 nodes, daily, encrypted, deduplicated
- **CrowdSec IPS** — 1400+ malicious IPs blocked at firewall, community threat intel
- **Terraform IaC** — entire cluster defined as code, importable state
- **AI self-healing** — media-monitor agent auto-fixes containers, torrents, VPN, permissions
- **Dual-channel Discord alerts** — all watchdogs and bots report to both Discord servers
- **Zero cloud dependencies** — everything self-hosted (except Cloudflare tunnel for external access)

---

## License

MIT — use this as inspiration for your own homelab.
