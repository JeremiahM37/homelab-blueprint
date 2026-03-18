# Lessons Learned

Hard-won knowledge from building and maintaining this homelab. Sorted by category.

---

## GPU Passthrough

- **Single GPU passthrough means headless host.** If the GPU you're passing through is the only one, the host console goes black. Manage everything via SSH or Proxmox web UI from another machine.
- **All PCI functions must be passed.** For NVIDIA GPUs, that's typically 4 functions: video, audio, USB controller, serial bus. Miss one and the guest may not initialize the GPU.
- **Update initramfs after any VFIO change.** `update-initramfs -u -k all && update-grub && reboot` — forgetting this is the most common reason passthrough "doesn't work."

## Game Streaming (Sunshine/Moonlight)

- **KMS vs X11 capture matters.** On gamescope (SteamOS/Bazzite), the Xwayland root framebuffer can be black even while games render fine. `capture=x11` will give you a black screen with just a cursor. Always use `capture=kms`.
- **Two different failure modes.** `503 failed to initialize video capture` = display/DPMS issue (fixable by toggling connector). Black screen + cursor = wrong capture backend (must force KMS).
- **"Ports listening" doesn't mean capture works.** Sunshine can be fully up and responding to API calls while capturing a black screen. Always verify the capture mode in logs.
- **AV1 encoding requires RTX 4000+.** RTX 2070 only supports H.264 and HEVC via NVENC.
- **Systemd user services need the right session context.** Launching Sunshine from a system-level service doesn't work (cgroup blocks XWayland). It must run inside the gamescope session.

## Docker / Containers

- **Permission errors show as "error" state in qBit.** If qBittorrent shows a torrent in error state, it's almost always `chown 1000:1000` needed on the download directory.
- **`network_mode: "service:gluetun"` means shared fate.** If gluetun restarts, all dependent containers lose networking. Order your restart logic accordingly.
- **Container restarts kill in-progress state.** Job queues, download progress, and other in-memory state is lost on restart. Don't restart containers just to "fix" transient issues.
- **DNS search domains leak into containers.** If your host has a search domain (e.g., from DHCP), containers inherit it. Add `dns_search: [""]` to prevent DNS resolution weirdness.

## Download Clients

- **IPFS gateways are unreliable.** Cloudflare-IPFS, gateway.ipfs.io, Pinata — all return 403 or timeout. Use direct download links (LibGen mirrors) instead.
- **Seeder counts lie.** Some indexers (especially LimeTorrents) inflate seeder counts. Verify with multiple sources or check actual connected peers in qBittorrent.
- **Magnet links from bare info_hash have no trackers.** They rely on DHT which is slow. Add announce URLs manually for faster peer discovery.
- **Share ratio limits can delete active downloads.** If qBit's ratio limit is set to auto-remove, it can delete a torrent + files that haven't finished downloading. Check your ratio settings.
- **Bulk collection torrents are huge.** Some sources package content as multi-GB collection files, not individual items. Check torrent contents before downloading.

## Book Pipeline

- **Anna's Archive download flow has specific steps.** Search → `ads.php?md5=...` → extract `get.php` link → direct download. Don't try to use `file.php` (IPFS only, broken).
- **Web novel scraping works best with `--all --single`.** This produces a single EPUB file with all chapters, instead of one file per chapter.

## Proxmox

- **pveproxy HTTP API is unreliable from external networks.** Always use `pvesh` via SSH instead of making REST API calls to the Proxmox web port.
- **Immutable OS (Bazzite) always shows root at 100%.** This is composefs — it's normal. Check `/var/home` for actual disk usage.

## n8n Workflow Automation

- **`fetch()` doesn't exist in Code nodes.** Use HTTP Request nodes for any external calls.
- **No `executeCommand` node in v2.x.** Use docker-socket-proxy for container operations.
- **Fan-out patterns cause timing errors.** Trigger → multiple parallel nodes → merge will fail. Use sequential chains instead.
- **Gluetun API returns body as string.** The response may be in `.data` as a raw string (content-type mismatch). Check both `.data.includes('...')` and the parsed property.
- **403 from qBit means it's running.** qBit returns 403 when it needs auth — that's healthy. Only ECONNREFUSED/ETIMEDOUT means it's actually down.
- **SSH credentials in n8n are tricky.** The private key must be in the credential data (not just the node config). Host, port, and username should be in both places.

## AMD GPU / ROCm

- **Nightly wheels may be required for new GPUs.** The Radeon 8060S (gfx1151) only works with ROCm nightly builds, not stable releases.
- **No HSA_OVERRIDE_GFX_VERSION needed** with native nightly kernels. If you find yourself setting this, you're probably using the wrong PyTorch build.
- **Ollama checks MemFree, not MemAvailable.** Large models may refuse to load even with plenty of reclaimable memory. Drop caches first: `echo 3 > /proc/sys/vm/drop_caches`.

## General

- **DAS mount is a hard dependency.** All media services fail if the USB DAS disconnects. First troubleshooting step: `mountpoint /mnt/storage`.
- **DHCP IPs change on reboot.** Use Tailscale for stable addressing to VMs that don't have static IPs.
- **Wake-on-LAN is worth configuring.** Saves you a physical trip to power on a machine after maintenance.
- **Anti-bot JavaScript on some sites can't be bypassed server-side.** Vimm.net's protection requires real browser JS execution. Use alternative sources (Myrient) instead.
