# Networking

Flat LAN with VPN for download clients, Tailscale mesh for stable inter-node access, a Cloudflare tunnel for selective external access, and an nginx + Authelia SSO reverse proxy for unified service access via `*.homelab.internal`.

---

## Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└──────────┬────────────────────┬──────────────────────────────┘
           │                    │
    ┌──────▼──────┐     ┌──────▼──────┐
    │ Cloudflare  │     │   Mullvad   │
    │   Tunnel    │     │ WireGuard   │
    │(cloudflared)│     │  (gluetun)  │
    └──────┬──────┘     └──────┬──────┘
           │                    │
    ┌──────▼────────────────────▼─────────────────────────────┐
    │                    LAN (flat /24)                         │
    │                                                          │
    │  ┌──────────┐   ┌──────────────┐   ┌────────────────┐  │
    │  │   pve    │   │ MediaServer  │   │   AIServer     │  │
    │  │          │   │              │   │                │  │
    │  │  VM 103  │   │   LXC 200   │   │ LXC 100-105   │  │
    │  │(bridged) │   │  (bridged)  │   │  (bridged)     │  │
    │  └──────────┘   └──────────────┘   └────────────────┘  │
    │                                                          │
    │  ◄──────── Tailscale mesh (overlay) ────────►           │
    └──────────────────────────────────────────────────────────┘
```

---

## LAN

All Proxmox nodes and their guests are on a flat `/24` network. Each LXC/VM gets a bridged interface with its own IP. No VLANs, no complex routing.

- Proxmox nodes: Static IPs
- LXC containers: Static IPs (configured in Proxmox)
- Gaming VM: DHCP (IP changes on reboot — use Tailscale for stability)

---

## Tailscale

Tailscale provides a WireGuard-based mesh network overlay. Every node gets a stable 100.x.x.x IP that works regardless of LAN changes.

**Use cases**:
- Stable SSH to the gaming VM (DHCP LAN IP is unreliable)
- n8n watchdog pings the gaming VM via Tailscale (more reliable than LAN for frozen VM detection)
- Cross-site access if nodes move to different networks

---

## VPN (Gluetun + Mullvad)

All download traffic routes through a Mullvad WireGuard VPN via the gluetun container.

### How It Works

```yaml
# Containers that need VPN use gluetun's network
qbittorrent:
  network_mode: "service:gluetun"

librarr:
  network_mode: "service:gluetun"

gamarr:
  network_mode: "service:gluetun"
```

- Gluetun establishes a WireGuard tunnel to Mullvad
- Containers sharing gluetun's network have ALL traffic routed through the tunnel
- Ports are exposed on the gluetun container (not on the service containers)
- Kill switch: If VPN drops, no traffic leaks (gluetun blocks non-tunnel traffic)

### Port Mapping

Since VPN'd containers share gluetun's network namespace, ports are mapped on gluetun:

```yaml
gluetun:
  ports:
    - "8080:8080"    # qBittorrent WebUI
    - "5050:5050"    # Librarr
    - "5057:5001"    # Gamarr (note: different host vs container port)
    - "8001:8000"    # Gluetun control API
```

### Monitoring

The VPN leak detection workflow verifies the tunnel is active by checking the public IP endpoint. Any HTTP response (even errors) means the tunnel is up. Only network-level failures indicate a VPN problem.

---

## Cloudflare Tunnel

The `cloudflared` container establishes an outbound-only tunnel to Cloudflare, allowing external access to select services without exposing any ports on the router.

**Benefits**:
- No port forwarding needed on the router
- DDoS protection via Cloudflare
- Access control via Cloudflare Access policies
- SSL/TLS termination at Cloudflare edge

**Architecture**:
```
Internet → Cloudflare Edge → cloudflared (outbound tunnel) → internal services
```

Only explicitly configured services are exposed. Everything else is LAN-only.

---

## Reverse Proxy + SSO (nginx + Authelia)

All Docker services are accessible via `https://<service>.homelab.internal` through an nginx reverse proxy with Authelia single sign-on, replacing direct IP:port access for browser users.

### Components

```
Browser ──► dnsmasq (*.homelab.internal → YOUR_DOCKER_HOST_IP)
         ──► nginx (port 443, wildcard cert)
              ├── auth_request → Authelia (port 9091) → Remote-User header
              └── proxy_pass → backend service (internal port)
```

- **nginx**: 34 subdomain server blocks, self-signed wildcard cert (`*.homelab.internal`, 10-year expiry)
- **Authelia**: File-based user auth, one-factor, session cookie scoped to `.homelab.internal`
- **dnsmasq**: Runs on the Docker host (port 53), resolves `*.homelab.internal` to the Docker host IP

### Auth Tiers

| Tier | Behavior | Services |
|------|----------|----------|
| **1 — True SSO** | Authelia authenticates, passes `Remote-User` header; service skips its own login | Sonarr, Radarr, Prowlarr, Bazarr, Grafana, n8n, Paperless |
| **2 — Authelia gate** | Authelia authenticates; service has no built-in auth | Homepage, it-tools, Stirling PDF, Tdarr, Pulse, Sentinel |
| **3 — Passthrough** | nginx proxies without `auth_request`; service uses its own login | Jellyfin, qBittorrent, Audiobookshelf, Kavita, Portainer, Uptime Kuma, Jellyseerr, GameVault, RoMM, Linkwarden, Librarr, Mealie, Homebox, Calibre-Web, Shelfarr, Changedetection, SearXNG, Gamarr, Discord Bot, and others |

### Tier 1 Configuration

Services that support `Remote-User` header auth:

| Service | Setting |
|---------|---------|
| Sonarr / Radarr / Prowlarr | `AuthenticationMethod: External` in `config.xml` |
| Bazarr | `AuthenticationMethod: External` in `config.xml` |
| Grafana | `GF_AUTH_PROXY_ENABLED=true` environment variable |
| n8n | `N8N_AUTH_HEADER=Remote-User` environment variable |
| Paperless | `PAPERLESS_ENABLE_HTTP_REMOTE_USER=true` environment variable |

### Key Files (LXC 200)

```
/opt/docker/nginx-proxy/nginx.conf           # 34 server blocks
/opt/docker/authelia/configuration.yml        # Session, access control, storage
/opt/docker/authelia/users_database.yml       # File-based user database
/opt/docker/nginx-proxy/certs/homelab.crt     # Self-signed wildcard cert
/opt/docker/nginx-proxy/certs/homelab.key     # Wildcard private key
/etc/dnsmasq.d/homelab.conf                   # *.homelab.internal → Docker host IP
```

### CA Certificate Distribution

Devices must trust the self-signed CA to avoid browser warnings:

```
http://YOUR_AISERVER_IP:9105/static/homelab-ca.crt
```

### Gotchas

- **Tier 1 services trust `Remote-User` blindly** — never expose them without Authelia in front, or anyone can impersonate any user
- **API/agent traffic** from Homelab API, Homelab Agent, and n8n still uses direct IP:port (not going through nginx)
- **Authelia session cookie** is domain-scoped to `.homelab.internal` — all subdomains share the login session

---

## DNS

- **Internal (Docker)**: Containers use Docker's internal DNS for service discovery (`prowlarr:9696`, `gluetun:8000`)
- **Internal (LAN)**: dnsmasq on the Docker host (port 53) resolves `*.homelab.internal` to the Docker host IP. Point device DNS settings at the Docker host IP.
- **Remote (Tailscale)**: Configure Tailscale split DNS to point `homelab.internal` to the Docker host IP for `*.homelab.internal` resolution over Tailscale.
- **External**: Standard ISP DNS or Cloudflare (1.1.1.1)
- **Gotcha**: If the host has a DNS search domain configured, containers may inherit it. Add `dns_search: [""]` in the compose file to prevent pollution.

---

## Inter-Service Communication

Services communicate via Docker networks:

- **proxy** network: Services that need external access
- **internal** network: Backend databases, inter-service APIs

Example: Prowlarr internal API URLs use container names (`prowlarr:9696`), not `localhost`. If calling from the host, use the mapped port (`localhost:9696`). If calling from another container via gluetun, replace `localhost` with the container name.

---

## Wake-on-LAN

All three Proxmox nodes have WoL configured via `pvesh set /nodes/{node}/config --wakeonlan {mac}`. Useful for remote power-on after maintenance shutdowns.
