# Homelab Ansible Playbook

Deploy the entire homelab stack on fresh Proxmox hardware. This playbook creates LXC containers, installs Docker with 55+ services, configures GPU passthrough, sets up SSO, centralized logging, automated backups, and AI/ML workloads.

## Prerequisites

- **3 Proxmox VE nodes** installed and accessible via SSH
- **Network**: All nodes on the same LAN subnet, static IPs assigned
- **Storage**: DAS mounted on MediaServer at `/mnt/storage` (for media + backups)
- **Ansible**: Install on your control machine:
  ```bash
  pip install ansible
  ansible-galaxy collection install community.general
  ```

## Setup

1. Copy the example inventory and fill in your values:
   ```bash
   cp inventory.example.yml inventory.yml
   ```

2. Edit `inventory.yml` with your:
   - Node IPs and SSH credentials
   - LXC container IPs and gateway
   - API keys and passwords (all `vault_*` variables)
   - VPN credentials

3. Test connectivity:
   ```bash
   ansible all -m ping
   ```

## Usage

### Full deploy (everything, in order)

```bash
ansible-playbook playbook.yml
```

### Deploy specific components

```bash
# Base setup on all nodes (packages, SSH, timezone, temp-api)
ansible-playbook playbook.yml --tags common

# Create LXC containers
ansible-playbook playbook.yml --tags lxc

# Docker host with 55+ services
ansible-playbook playbook.yml --tags docker

# Ollama + Open-WebUI AI stack
ansible-playbook playbook.yml --tags ai

# Authelia + nginx SSO reverse proxy
ansible-playbook playbook.yml --tags sso

# Loki + Promtail centralized logging
ansible-playbook playbook.yml --tags monitoring

# Restic backup setup
ansible-playbook playbook.yml --tags backups

# GPU passthrough (NVIDIA on pve, AMD iGPU on AIServer)
ansible-playbook playbook.yml --tags gpu

# Dev environment (LXC 104 — Claude Code, Docker, Node, Zellij)
ansible-playbook playbook.yml --tags dev

# AIServer host services (homelab-api, agent, doc-rag, nightly tests, web terminals)
ansible-playbook playbook.yml --tags aiserver
```

### Limit to a specific host

```bash
# Only run on MediaServer
ansible-playbook playbook.yml --limit mediaserver

# Only run Docker setup on LXC 200
ansible-playbook playbook.yml --tags docker --limit lxc200
```

## What each role does

| Role | Tag | Description |
|------|-----|-------------|
| `common` | `common` | SSH hardening, apt packages, timezone, temp-api on all nodes |
| `gpu-passthrough` | `gpu` | IOMMU, vfio-pci (NVIDIA), AMD iGPU device passthrough for LXCs |
| `proxmox-lxcs` | `lxc` | Creates LXC containers with specs from `group_vars/all.yml` |
| `docker-host` | `docker` | Installs Docker, copies compose file, generates `.env`, starts services |
| `sso` | `sso` | Authelia + nginx reverse proxy + dnsmasq for `*.homelab.internal` |
| `monitoring` | `monitoring` | Loki + Promtail for centralized logging, Grafana datasource |
| `ollama` | `ai` | Ollama + model pulls + Open-WebUI on LXC 102 |
| `aiserver` | `aiserver` | homelab-api, homelab-agent, doc-rag, nightly tests, web terminals, Claude loop |
| `backups` | `backups` | Restic to DAS, daily timers, retention policy, status API |
| `dev-environment` | `dev` | Docker, Node.js, Python, Zellij, Claude Code on LXC 104 |

## Manual steps after Ansible

The playbook handles infrastructure and service deployment. These require manual setup:

1. **Cloudflare Tunnel** -- Log into the Cloudflare dashboard and generate a tunnel token, then set `vault_cloudflare_tunnel_token` in your inventory.

2. **Tailscale** -- Run `tailscale up` on each node and authenticate. Tailscale IPs are assigned dynamically.

3. **Service initial setup** -- First-run wizards for:
   - Jellyfin (library paths, user creation)
   - Sonarr/Radarr (indexer + download client config)
   - Prowlarr (add indexers)
   - Jellyseerr (connect to Jellyfin)
   - qBittorrent (change default password)
   - Uptime Kuma (add monitors)
   - Grafana (import dashboards)

4. **Custom Go services** -- Clone and build Librarr, Sentinel, and Gamarr into the Docker compose directory:
   ```bash
   cd /opt/docker
   git clone https://github.com/JeremiahM37/librarr librarr-go
   git clone https://github.com/JeremiahM37/sentinel sentinel
   git clone https://github.com/JeremiahM37/gamarr gamarr
   docker compose build librarr sentinel gamarr
   docker compose up -d librarr sentinel gamarr
   ```

5. **AIServer Python services** -- Clone and set up homelab-api, homelab-agent, doc-rag:
   ```bash
   # Each service needs its own repo/venv/config
   cd /home/admin/homelab-api && python3 -m venv venv && pip install -r requirements.txt
   # Repeat for homelab-agent, doc-rag
   ```

6. **n8n workflows** -- Import workflow JSON files manually through the n8n UI.

7. **CrowdSec** -- Register with the CrowdSec Hub, install collections, configure the firewall bouncer on the MediaServer host.

8. **Homepage dashboard** -- Configure `services.yaml`, `bookmarks.yaml`, `widgets.yaml` in `/opt/docker/homepage/`.

9. **Discord bot** -- Create a Discord application, generate a bot token, invite to your servers.

10. **Bazzite Gaming VM** -- Install Bazzite OS manually on VM 103, configure GPU passthrough in the Proxmox UI, set up Sunshine/Moonlight.

11. **SSL CA trust** -- Distribute the self-signed CA certificate to client devices.

12. **GPU passthrough reboot** -- After running `--tags gpu`, reboot the affected nodes for IOMMU changes to take effect.

## File structure

```
ansible/
  ansible.cfg                    # Ansible configuration
  inventory.example.yml          # Template inventory (copy to inventory.yml)
  playbook.yml                   # Main playbook
  group_vars/
    all.yml                      # Default variables (no secrets)
  roles/
    common/tasks/main.yml        # Base setup for all nodes
    proxmox-lxcs/
      tasks/main.yml             # Create LXC containers
      defaults/main.yml          # LXC specs
    docker-host/
      tasks/main.yml             # Docker install + compose deploy
      templates/docker-env.j2    # .env file template
      defaults/main.yml          # Docker defaults
    aiserver/
      tasks/main.yml             # AIServer host services
      templates/*.j2             # systemd service/timer templates
      defaults/main.yml
    ollama/
      tasks/main.yml             # Ollama + Open-WebUI
      defaults/main.yml
    sso/
      tasks/main.yml             # Authelia + nginx + dnsmasq
      templates/
        authelia-config.yml.j2   # Authelia config
        nginx.conf.j2            # nginx with 3-tier auth
        users_database.yml.j2    # Authelia user DB
      defaults/main.yml
    monitoring/
      tasks/main.yml             # Loki + Promtail
      templates/
        loki-config.yml.j2       # Loki config
        promtail-config.yml.j2   # Promtail scrape config
      defaults/main.yml
    backups/
      tasks/main.yml             # Restic setup
      templates/
        backup-script.sh.j2      # Per-node backup script
      defaults/main.yml
    gpu-passthrough/
      tasks/main.yml             # IOMMU, vfio-pci, AMD iGPU
      defaults/main.yml
    dev-environment/
      tasks/main.yml             # Claude Code, Docker, Node, Zellij
      defaults/main.yml
```

## Security notes

- `inventory.yml` is gitignored -- never commit it
- All secrets use `vault_*` variable names for easy identification
- Consider using `ansible-vault` to encrypt your inventory:
  ```bash
  ansible-vault encrypt inventory.yml
  ansible-playbook playbook.yml --ask-vault-pass
  ```
- The self-signed wildcard cert is generated during the SSO role -- distribute the CA to trusted devices only
- Tier 1 SSO services trust the `Remote-User` header blindly -- never expose them without Authelia in front
