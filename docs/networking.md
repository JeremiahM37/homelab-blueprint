# Networking

Flat LAN with VPN for download clients, Tailscale mesh for stable inter-node access, and a Cloudflare tunnel for selective external access.

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

bookbounty:
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
    - "5050:5050"    # BookBounty
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

## DNS

- Internal: Containers use Docker's internal DNS for service discovery (`prowlarr:9696`, `gluetun:8000`)
- External: Standard ISP DNS or Cloudflare (1.1.1.1)
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
