# Recreating the Stack from Scratch

A single ordered runbook: start with bare Proxmox hardware, end with the full
stack running. Every command is meant to be run in the order shown. All values
in this doc are placeholders or example IPs (`192.168.1.x` examples like
`.20/.30/.222`) — substitute your own.

The layers, in order:

| # | Layer | Tool | What it produces |
|---|-------|------|------------------|
| 1 | Proxmox prep | manual | nodes, storage, API token, LXC template, SSH keys |
| 2 | Guest shells | Terraform (`terraform/`) | LXC 100–105 on AIServer, LXC 200 on MediaServer |
| 3 | In-guest convergence | Ansible (`ansible/`) | packages, Docker, SSO, monitoring, backups, AI stack |
| 4 | Service stack | Docker Compose (LXC 200) | 55+ containers |
| 5 | Manual finishers | manual | Tailscale, tunnels, first-run wizards |

---

## 0. Hardware assumptions

- **Two or more Proxmox VE 8/9 nodes** on one flat LAN. The blueprint names
  them `AIServer` (AI/LXC node, lots of RAM — the reference box has 128 GB)
  and `MediaServer` (media node, ~28 GB). A third gaming node with an NVIDIA
  GPU is optional (see `terraform/vms.tf`, commented out).
- **External storage** (DAS/NAS disk) attached to MediaServer, formatted (btrfs
  in the reference build) — this holds all media and the backup repo.
- A **control machine** (laptop or one of the nodes) with `git`, `terraform`,
  and `python3`/`pip` for Ansible.
- A LAN router where you can set DHCP reservations (or you assign static IPs).

Adapt-to-taste knobs (single node? rename nodes?) are called out inline.

## 1. Proxmox preparation (per node, manual)

1. **Install Proxmox VE** on each node; give each a static IP or DHCP
   reservation (examples: MediaServer `192.168.1.20`, AIServer `192.168.1.30`).
2. **Cluster them** (optional but assumed): on the first node
   `pvecm create homelab`, on the others `pvecm add 192.168.1.20`.
3. **SSH keys**: from the control machine, `ssh-copy-id root@192.168.1.20` and
   `ssh-copy-id root@192.168.1.30`. Terraform (provider SSH) and Ansible both
   assume key-based root SSH to the nodes.
4. **Storage names**: the IaC uses Proxmox's defaults — `local` (templates)
   and `local-lvm` (guest disks). If your storage is named differently
   (e.g. ZFS pool `rpool-data`), change `datastore_id` in
   `terraform/containers.tf` and `lxc_template_storage`/`lxc_disk_storage` in
   `ansible/roles/proxmox-lxcs/defaults/main.yml`.
5. **Mount the DAS on MediaServer** at `/mnt/storage` and persist it:

   ```bash
   blkid /dev/sdX1                       # note the UUID
   mkdir -p /mnt/storage
   echo 'UUID=<YOUR_DAS_UUID> /mnt/storage btrfs defaults,nofail 0 2' >> /etc/fstab
   mount -a && mkdir -p /mnt/storage/media /mnt/storage/backups
   ```

6. **API token for Terraform** (Proxmox UI, once per cluster):
   - Datacenter → Permissions → Users → Add: `terraform@pve`
   - Datacenter → Permissions → API Tokens → Add: user `terraform@pve`,
     token ID `iac`, **untick "Privilege Separation"**
   - Datacenter → Permissions → Add → User Permission: path `/`, user
     `terraform@pve`, role `Administrator` (scope down later if you care)
   - Record the token as `terraform@pve!iac=<uuid>` — you get the uuid once.
7. **LXC template**: the Ansible `lxc` tag downloads it automatically
   (`pveam update && pveam download local debian-12-standard_12.7-1_amd64.tar.zst`).
   If you provision with Terraform first, run that command manually on each
   node beforehand — Terraform expects the template to already exist.

## 2. Terraform — guest shells

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars        # endpoint, API token, root password, SSH key
terraform init
terraform plan                  # review: LXCs 100–105 + 200
terraform apply
```

- Node names in `containers.tf` are `AIServer` and `MediaServer` — change
  `node_name` if your nodes are named differently.
- LXC 103 (valheim) carries a static example IP (`192.168.1.40/24`) — edit it.
- **Existing guests?** Import instead of recreating — see `terraform/README.md`.
- GPU passthrough `lxc.cgroup2`/`lxc.mount.entry` lines can't be expressed by
  the provider; the Ansible `gpu` tag adds them.

Alternatively, skip Terraform entirely: the Ansible `lxc` tag creates the same
containers via `pct create` from `group_vars/all.yml`. Pick one owner per
guest, not both.

## 3. Ansible — in-guest convergence

```bash
cd ansible
pip install ansible-core
ansible-galaxy collection install -r requirements.yml
cp inventory.example.yml inventory.yml
$EDITOR inventory.yml           # every YOUR_* placeholder — see section 6
ansible all -m ping             # connectivity check before anything else
```

Then run the playbook. Full run is `ansible-playbook playbook.yml`, but on a
truly cold cluster this order avoids chicken-and-egg problems:

```bash
ansible-playbook playbook.yml --tags common       # packages, SSH, temp-api
ansible-playbook playbook.yml --tags gpu          # IOMMU/vfio — then REBOOT the GPU nodes
ansible-playbook playbook.yml --tags lxc          # create LXCs (skip if Terraform did it)
# start the LXCs, note their DHCP IPs (pct list / your router), then fill
# lxc200/lxc102/lxc104 ansible_host values in inventory.yml
ansible-playbook playbook.yml --tags docker       # LXC 200: Docker + compose + .env + up -d
ansible-playbook playbook.yml --tags sso          # Authelia + nginx + dnsmasq
ansible-playbook playbook.yml --tags monitoring   # Loki + Promtail + Grafana datasource
ansible-playbook playbook.yml --tags ai           # LXC 102: Ollama + models + Open-WebUI
ansible-playbook playbook.yml --tags aiserver     # AIServer host services (see caveat below)
ansible-playbook playbook.yml --tags backups      # restic repo + timers + status API
ansible-playbook playbook.yml --tags dev          # LXC 104 dev environment
```

Caveats:

- The **`ai` tag downloads ~40 GB of models** — expect it to run a while.
- The **`aiserver` role deploys systemd units only**; the Python services
  themselves (homelab-api, homelab-agent, doc-rag) are separate projects you
  clone and venv into `/home/admin/<name>` (units point there). Services stay
  dead-but-enabled until you do.
- The LXCs get **root SSH via the Proxmox host key** only if your key was
  injected (Terraform `ssh_public_key`) — otherwise set a root password with
  `pct exec <id> -- passwd` before pointing Ansible at them.

## 4. LXC 200 — Docker stack bring-up

The `docker` tag does all of this for you. Manual equivalent (or for
re-runs):

```bash
ssh root@192.168.1.222          # your LXC 200 IP
cd /opt/docker
cp docker-compose.example.yml docker-compose.yml   # if not copied by Ansible
cp .env.example .env && $EDITOR .env               # every secret — see section 6
docker compose config -q        # sanity: env substitution resolves
docker compose up -d
```

Then build the custom Go services (images are not on any registry):

```bash
cd /opt/docker
git clone https://github.com/JeremiahM37/librarr librarr-go
git clone https://github.com/JeremiahM37/sentinel sentinel
git clone https://github.com/JeremiahM37/gamarr gamarr
docker compose build librarr sentinel gamarr
docker compose up -d librarr sentinel gamarr
```

Note: several API keys in `.env` (Sonarr/Radarr/Prowlarr/Jellyfin/…) **don't
exist until those apps first start**. Bring the stack up with placeholder
values, collect the keys from each app's Settings → General, update `.env`
(or `inventory.yml` + re-run `--tags docker`), then
`docker compose up -d --force-recreate unpackerr librarr sentinel`.

## 5. DNS, SSO and remote access

- **dnsmasq** (installed by the `sso` tag on LXC 200) answers
  `*.homelab.internal` → LXC 200. Point your LAN clients' DNS at LXC 200
  (router DHCP option), or add per-device entries.
- **Authelia password hash**: generate with
  `docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'YOUR_SSO_PASSWORD'`
  and put the result in `vault_authelia_password_hash`.
- **Self-signed CA**: the `sso` tag generates
  `/opt/docker/nginx-proxy/certs/homelab.crt` — import it on client devices to
  silence TLS warnings.
- **Tailscale** (optional, remote access): `curl -fsSL https://tailscale.com/install.sh | sh && tailscale up`
  on each node/guest you want reachable; add a split-DNS rule for
  `homelab.internal` → LXC 200's Tailscale IP in the Tailscale admin console.
- **Cloudflare Tunnel** (optional, public access): create a tunnel in the
  Zero Trust dashboard, put its token in `TUNNEL_TOKEN`.

## 6. Every secret you must supply

No real secrets exist anywhere in this repo. You must provide, by file:

**`terraform/terraform.tfvars`** (gitignored)

| Placeholder | Purpose |
|-------------|---------|
| `proxmox_endpoint` | Proxmox API URL, e.g. `https://192.168.1.30:8006` |
| `proxmox_api_token` | `terraform@pve!iac=<uuid>` from step 1.6 |
| `root_password` | root password set inside new containers |
| `ssh_public_key` | your public key, injected into containers |

**`ansible/inventory.yml`** (gitignored; consider `ansible-vault encrypt`)

| Placeholder | Purpose |
|-------------|---------|
| `ansible_host` per node/guest | node and LXC IPs |
| `lan_gateway`, `docker_host_ip`, `das_uuid` | network + storage identity |
| `ssh_authorized_keys` (optional) | key(s) pushed to all nodes |
| `ansible_become_password` (aiserver, lxc104) | sudo passwords for non-root hosts |
| `vault_vpn_private_key`, `vault_vpn_address` | WireGuard credentials from your VPN provider (gluetun) |
| `vault_qbit_user` / `vault_qbit_password` | qBittorrent WebUI login |
| `vault_prowlarr/sonarr/radarr/jellyfin/jellyseerr_api_key` | *arr + media API keys (from each app after first run) |
| `vault_librarr_user` / `vault_librarr_password` / `vault_torznab_api_key` | Librarr auth + its Torznab key (you invent these) |
| `vault_abs_token`, `vault_kavita_api_key` | Audiobookshelf token, Kavita key (from their UIs) |
| `vault_sentinel_discord_webhook`, `vault_discord_webhook_url[_2]` | Discord webhooks for alerts |
| `vault_db_user` / `vault_db_password` / `vault_db_root_password` | shared Postgres/MariaDB credentials (you invent) |
| `vault_paperless_secret`, `vault_linkwarden_secret` | random secrets — `openssl rand -hex 32` |
| `vault_n8n_user` / `vault_n8n_password` | n8n basic-auth login |
| `vault_cloudflare_tunnel_token` | Cloudflare Zero Trust tunnel token |
| `vault_discord_bot_token` | Discord bot token (Discord developer portal) |
| `vault_authelia_jwt_secret` / `_session_secret` / `_storage_encryption_key` | random secrets — `openssl rand -hex 32` each |
| `vault_authelia_user` / `_password_hash` / `_display_name` / `_email` | your SSO account (argon2 hash — see section 5) |
| `vault_restic_password` | encrypts the backup repo — **losing it loses the backups** |
| `vault_homelab_api_key`, `vault_proxmox_api_token`, `vault_mealie_api_token` | AIServer host-service integrations |

**`/opt/docker/.env` on LXC 200** — generated from the inventory by the
`docker` tag; only edit by hand on a manual (non-Ansible) bring-up. Variable
list: repo-root `.env.example`.

## 7. Post-deploy verification

From the control machine (substitute your IPs):

```bash
# Proxmox + guests
ssh root@192.168.1.30 'pct list'                          # LXCs 100–105 running
ssh root@192.168.1.20 'pct list && mountpoint /mnt/storage'   # 200 + DAS mounted
ssh root@192.168.1.222 'readlink /data/media'             # -> /mnt/storage/media

# Docker stack (LXC 200)
ssh root@192.168.1.222 'docker ps --format "{{.Names}} {{.Status}}" | grep -vi "up" || echo ALL-UP'
curl -fsS http://192.168.1.222:8096/health                # Jellyfin
curl -fsS http://192.168.1.222:9696/ping                  # Prowlarr
curl -fsS http://192.168.1.222:8080 -o /dev/null -w '%{http_code}\n'   # qBittorrent (via gluetun)
curl -fsS http://192.168.1.222:8001/v1/publicip/ip        # gluetun: VPN exit IP (must NOT be your WAN IP)
curl -fsSk https://192.168.1.222 -H 'Host: auth.homelab.internal' -o /dev/null -w '%{http_code}\n'  # Authelia via nginx
dig +short jellyfin.homelab.internal @192.168.1.222       # dnsmasq answers

# AI stack
curl -fsS http://<LXC102_IP>:11434/api/tags               # Ollama models present
curl -fsS http://<LXC102_IP>:8080 -o /dev/null -w '%{http_code}\n'    # Open-WebUI

# Node services + backups
curl -fsS http://192.168.1.30:9101/                       # temp-api (each node)
curl -fsS http://192.168.1.20:9102/                       # backup-status-api
ssh root@192.168.1.30 'systemctl list-timers backup-* nightly-tests.timer --no-pager'
ssh root@192.168.1.20 'RESTIC_PASSWORD=<YOUR_RESTIC_PASSWORD> restic -r /mnt/storage/backups/homelab snapshots | tail -5'
```

All green? Finish with the first-run wizards listed in
[ansible/README.md § Manual steps](../ansible/README.md#manual-steps-after-ansible)
and the service docs in [docs/](.).
