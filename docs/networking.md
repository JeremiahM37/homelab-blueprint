# Networking

Two Proxmox hosts, DHCP on the LAN, Tailscale for stable addressing, and separate
paths for private browser access and explicitly published services.

## Topology

```text
Internet
  ├─ Cloudflare Tunnel → selected public services only
  ├─ Tailscale mesh → hosts, service LXCs and private HTTPS
  └─ UniFi router → managed switch → flat LAN
       ├─ MediaServer → LXC 200 → Docker, nginx, dnsmasq, Omada
       └─ AIServer → host services + inference, research and agent LXCs
```

The former gaming host is retired. Valheim's retained LXC has no Tailscale
client; its configured public access uses an outbound playit.gg agent. It was
stopped at the September 2026 audit.

## Addressing and DNS

Hosts and guests obtain LAN addresses by DHCP. LXC 200 and the managed switch
have DHCP reservations. A router subnet change requires reviewing those
reservations, even when guests themselves use DHCP.

The private deployment keeps stable addresses in `homelab.env`, read through
`homelab_config.py`. Router/switch LAN values live in `lan.env`; one helper
propagates them. Public examples use placeholders or names.

- **Service traffic:** use Tailscale IPs or MagicDNS hostnames.
- **Docker traffic:** use container names on the appropriate Docker network.
- **Internal service names:** Tailscale split DNS sends `homelab.internal` to
  dnsmasq on LXC 200. Its answers currently identify the tailnet address.
- **LAN-only clients:** router DNS does not make tailnet-only answers reachable.
  Changing DHCP DNS alone is not a solution; LAN access needs appropriate DNS
  answers and a reachable route together.

DHCP renewals once overwrote AIServer's resolver file and silently removed
MagicDNS. Prepending Tailscale's DNS resolver in `dhclient.conf` preserves it
through renewal, with the DHCP resolver as fallback. When only one machine
loses name resolution, inspect its live resolver configuration first.

A two-node Proxmox cluster needs both votes to stay quorate. A QDevice is a
separate design decision, not something this blueprint assumes is installed.

## Browser entry points

| Surface | Address pattern | Authentication / certificate |
|---------|-----------------|------------------------------|
| Homepage and service gateways | `https://<service>.homelab.internal` | Local CA; gateway or service login |
| Mobile PWA | `https://<aiserver-tailnet-name>/app` | Tailnet reachability; trusted TLS |
| Lectern | `https://<aiserver-tailnet-name>:8443` | Direct TLS and Tailscale peer identity |
| PWA Proxmox console | `https://<aiserver-tailnet-name>:10443` | Tailnet Serve proxy; Proxmox login |
| Agent Desk | `https://<agent-desk-tailnet-name>/vnc.html` | Tailnet access; desktop password |
| Embedded Grafana | `https://<docker-tailnet-name>:3443` | Tailnet Serve; anonymous Viewer |

Tailscale **Serve** is private to the tailnet; Funnel is not used. Check the
`AllowFunnel` field of `tailscale serve status --json` rather than grepping
`tailscale funnel status`, which also displays private Serve entries.

Serve a second app on a **different TLS port** from its HTTP listener.
Lectern terminates its own TLS to retain the real peer address: behind a
loopback proxy it could not distinguish a phone from a local agent for approvals.

## Reverse proxy and SSO

nginx on LXC 200 redirects port 80 to HTTPS using one catch-all server block.
Per-service virtual hosts listen on 443. A local wildcard certificate covers
`*.homelab.internal`; devices must trust the local CA.

| Class | Behavior | Examples |
|-------|----------|----------|
| Header SSO | Gateway login supplies `Remote-User` | Sonarr, Radarr, Prowlarr, Bazarr, Grafana, n8n, Paperless |
| Gateway gate | Authelia protects an app without its own login | Homepage, IT-Tools, Stirling PDF, Tdarr, Pulse, Sentinel, Formwork |
| Service login | nginx passes through to the app's own authentication | Jellyfin, qBittorrent, Immich, Librarr, Portainer and others |
| Deployment-specific bypass | Private installation explicitly bypasses app login | Seafile; not a safe public default |

Do not expose a header-trusting backend directly to untrusted clients. Widget
and agent API calls may use private backend URLs with service credentials;
browser launch links retain the gateway where it supplies authentication.

Configuration lives under `/opt/docker/nginx-proxy/` and `/opt/docker/authelia/`.
Never publish generated configs containing keys, hashes or personal account IDs.

## Iframes and mixed content

HTTPS pages cannot embed HTTP apps or fetch HTTP resources. A real certificate
for a hostname does not validate an `https://<IP>` URL.

Proxmox's login cookie is `SameSite=Lax`. Homepage embeds
`https://proxmox.homelab.internal`; the mobile PWA uses its own hostname on
port 10443. A cross-site iframe can display a login form yet fail to retain
login. Both the cookie policy and `frame-ancestors` must permit the embed.

Use same-origin proxies for inline API/media resources. Otherwise provide a
normal link. [Dashboard](dashboard.md) records the current choices.

## VPN: Gluetun and Mullvad

qBittorrent, Librarr and Gamarr share Gluetun's network namespace:

```yaml
qbittorrent:
  network_mode: "service:gluetun"
```

Publish their ports on Gluetun: 8080 for qBittorrent, 5050 for Librarr,
5057→5001 for Gamarr, and 8001→8000 for the control API. Credentials stay in a
private environment file. `WIREGUARD_MTU=1280` addresses the observed PMTU
black hole where a handshake succeeded but traffic stalled.

A **recreated** Gluetun has a new container ID and namespace. Dependents may
remain attached to the dead namespace while their internal health checks pass.
The deployed guard compares namespace IDs and force-recreates affected
containers after Gluetun is healthy. A plain restart is insufficient in that case.

An HTTP response proves reachability, not VPN identity. Confirm routing using
`am.i.mullvad.net/json` from inside the tunnel. Report an unavailable probe
separately from a verified leak; track subscription expiry as another signal.
