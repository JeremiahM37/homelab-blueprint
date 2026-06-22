# Disaster Recovery

How to rebuild the homelab after losing a node — or everything. The honest
version: **no single tool rebuilds the cluster.** Recovery is four layers that
each own a different slice. Knowing which layer owns what is the whole game.

## The four layers

| Layer | Recovers | Does **not** recover |
|-------|----------|----------------------|
| **Terraform** (`/home/admin/terraform/`) | Container/VM **shells** — cores, memory, disk, hostname, on the right node | Installed software, app data, GPU passthrough, Tailscale, anything *inside* the guest |
| **restic** (`/mnt/storage/backups/homelab`) | Data + configs — `/home/admin`, `/opt/docker` (incl. the Chroma vector DB), `/etc/pve`, systemd units, LXC configs | Bulk media (excluded by design), caches/logs |
| **GitHub** | All open-source project code (librarr, gamarr, sentinel, homelab-ai, …) | Local-only uncommitted work — commit/push regularly |
| **Manual** | GPU passthrough lines, Tailscale auth, Ollama model pulls, app start | — (documented below) |

> Terraform uses `lifecycle { ignore_changes = all }` — the config is
> **documentation + shell-recreation**, deliberately not a live reconciler. It
> won't fight manual changes, and a stray `apply` won't recreate live guests.

## Backup inventory (what restic holds)

- **Repo:** `sftp:root@<mediaserver>:/mnt/storage/backups/homelab` (on the DAS), encrypted + deduplicated. Password stored on each node (not in this repo).
- **Schedule:** daily 3 AM via systemd timers per node. **Retention:** 7 daily / 4 weekly / 3 monthly.
- **Contents (verified):**
  - `aiserver` — `/home/admin` (host services + code), `/etc/pve`, systemd units
  - `lxc200-docker` — all of `/opt/docker` (the entire Docker stack + the Chroma volume), `docker-compose.yml` + `.env`
  - `pve` / `mediaserver-host` — Proxmox config, network, VFIO/modprobe, SSH keys
  - `lxc102/104/105` — per-LXC tarballs

## Restore runbook (full rebuild, in order)

1. **Proxmox nodes** — reinstall Proxmox; restore `/etc/pve`, network config, and (for the gaming node) GRUB/VFIO/modprobe from the restic `pve`/`mediaserver-host` snapshots.
2. **Container shells** — `cd /home/admin/terraform && terraform apply` to recreate the LXC/VM shells. (Or `pct restore` from a vzdump archive if you have one — faster for a single guest.)
3. **Data + configs** — `restic restore <snapshot> --target /` per guest/host to repopulate `/home/admin`, `/opt/docker`, etc.
4. **Bring services up:**
   - LXC 200: `cd /opt/docker && docker compose up -d` (restores all containers incl. Chroma).
   - AIServer host: `systemctl daemon-reload && systemctl enable --now <unit>` for each restored systemd service (doc-rag, homelab-api, mcpo-*, timers).
5. **Manual steps (not captured by the above):**
   - **GPU passthrough** (LXC 102/105): re-add the `lxc.cgroup2.devices.allow` + `lxc.mount.entry` lines to the container config (not supported by the TF provider).
   - **Gaming VM**: confirm IOMMU + `vfio-pci` binding (`10de:*` IDs) before starting.
   - **Tailscale**: re-authenticate each node (`tailscale up`).
   - **Ollama models**: re-pull on LXC 102 (`ollama pull <model>`) — model blobs aren't backed up.

## Known gaps / gotchas

- **Media is not backed up** (too large) — it's re-acquirable via the *arr stack, by design.
- **Ollama model blobs** are not backed up — re-pull them.
- **Cross-host restic permissions:** the repo lives on a shared DAS mount. AIServer/pve/MediaServer write snapshots via SFTP **as root** (mode `0660`); LXC 200 is **unprivileged** and reads the repo via the local mount, where root-owned files appear as `nobody` → "permission denied" → its backup silently fails. Fix: keep the repo world-readable (`chmod -R a+rX` the repo; content is encrypted so this is safe). The AIServer backup script now does this automatically after each run.
- **Verify restores periodically** — a backup you haven't test-restored is a hope, not a backup.
