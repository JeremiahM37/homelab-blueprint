# Homelab Blueprint

A three-node Proxmox cluster running media automation, gaming (with GPU passthrough + game streaming), AI/ML workloads, and self-hosted productivity tools — all on consumer hardware.

This repo documents the architecture, services, and lessons learned. No credentials or personal info — just the blueprint.

---

## Cluster Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Proxmox VE Cluster ("HomeServer")               │
│                        3 nodes · PVE 9.1.1                          │
├──────────────────┬──────────────────────┬───────────────────────────┤
│    Node: pve     │  Node: MediaServer   │     Node: AIServer        │
│  (Gaming/Dev)    │  (Media Stack Host)  │   (AI/ML Workloads)       │
│                  │                      │                           │
│  CPU: i7-9700K   │  CPU: Ryzen 7 8845HS │  CPU: Ryzen AI MAX+ 395  │
│  RAM: 32 GB      │  RAM: 28 GB          │  RAM: 128 GB             │
│  GPU: RTX 2070*  │  iGPU: Radeon 780M   │  iGPU: Radeon 8060S      │
│                  │                      │                           │
│  ┌────────────┐  │  ┌────────────────┐  │  ┌───────────────────┐   │
│  │ VM 103     │  │  │ LXC 200        │  │  │ LXC 100           │   │
│  │ Bazzite    │  │  │ Docker Host    │  │  │ Media Monitor     │   │
│  │ Gaming VM  │  │  │ 35+ containers │  │  │ (health agent)    │   │
│  │ 4c/24GB    │  │  │ 12c/24GB       │  │  ├───────────────────┤   │
│  │ GPU pass-  │  │  └────────────────┘  │  │ LXC 101           │   │
│  │ through    │  │                      │  │ Dev Workspace     │   │
│  └────────────┘  │                      │  ├───────────────────┤   │
│                  │                      │  │ LXC 102           │   │
│  * Only GPU in   │  DAS: 8TB btrfs      │  │ LLM Chat (Ollama) │   │
│    system —      │  (USB TerraMaster)   │  │ 32c/80GB          │   │
│    host goes     │                      │  ├───────────────────┤   │
│    headless      │                      │  │ LXC 105           │   │
│    when VM runs  │                      │  │ Research Env      │   │
│                  │                      │  │ GPU passthrough   │   │
│                  │                      │  │ 32c/48GB          │   │
│                  │                      │  └───────────────────┘   │
└──────────────────┴──────────────────────┴───────────────────────────┘
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
        │           └── gluetun VPN (Mullvad WireGuard)
        │                 ├── qBittorrent
        │                 ├── Librarr
        │                 └── Gamarr
        │
        └── AIServer node
              ├── LXC 100-105 — bridged LAN
              └── MCP server (Proxmox management)
```

### VPN Architecture

Download clients (qBittorrent, Librarr, Gamarr) route through a **gluetun** container running Mullvad WireGuard. Services that need VPN protection use `network_mode: "service:gluetun"` in Docker Compose and expose their ports through gluetun.

---

## Guests (VMs & Containers)

| VMID | Name | Node | Type | Resources | Purpose |
|------|------|------|------|-----------|---------|
| 100 | media-monitor | AIServer | LXC | 4c / 16 GB | Automated health monitoring agent |
| 101 | project-env | AIServer | LXC | 4c / 8 GB | Development workspace |
| 102 | openclaw | AIServer | LXC | 16c / 80 GB | Local LLM chat (Ollama + Open-WebUI) |
| 103 | gaming-bazzite | pve | VM | 7c / 28 GB | Gaming VM with GPU passthrough |
| 105 | research-env | AIServer | LXC | 32c / 48 GB | AI/ML research with GPU passthrough |
| 200 | docker-server | MediaServer | LXC | 12c / 24 GB | Main Docker host (35+ containers) |

---

## Documentation

| Doc | Description |
|-----|-------------|
| [Docker Services](docs/docker-services.md) | All 35+ containers running on LXC 200 |
| [Gaming VM](docs/gaming-vm.md) | Bazzite setup, GPU passthrough, Sunshine/Moonlight streaming |
| [Game Pipeline](docs/game-pipeline.md) | Automated game download → install → Steam library pipeline |
| [AI Stack](docs/ai-stack.md) | Ollama, Open-WebUI, research environments, GPU passthrough |
| [Monitoring](docs/monitoring.md) | n8n watchdog workflows, media-monitor agent, Uptime Kuma |
| [Media Stack](docs/media-stack.md) | Jellyfin, *arr apps, download automation |
| [Networking](docs/networking.md) | VPN, Cloudflare tunnel, Tailscale mesh |
| [Lessons Learned](docs/lessons-learned.md) | Gotchas, debugging tips, things that broke |
| [Docker Compose (example)](docker-compose.example.yml) | Sanitized compose file |

---

## Quick Stats

- **6 guests** across 3 nodes (5 LXC + 1 VM)
- **35+ Docker containers** on a single LXC
- **~168 GB total RAM** across the cluster
- **8 TB DAS** for media storage
- **GPU passthrough** on 2 nodes (NVIDIA for gaming, AMD for ML)
- **Automated pipelines** for media, games, ROMs, books, and health monitoring
- **Zero cloud dependencies** — everything self-hosted (except Cloudflare tunnel for external access)

---

## License

MIT — use this as inspiration for your own homelab.
