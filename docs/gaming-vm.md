# Gaming VM (Bazzite + GPU Passthrough)

A dedicated gaming VM running Bazzite (Fedora Atomic / SteamOS-like) with full NVIDIA GPU passthrough, game streaming via Sunshine/Moonlight, and automated game library management.

---

## VM Configuration

| Setting | Value |
|---------|-------|
| **Hypervisor** | Proxmox VE (QEMU/KVM) |
| **OS** | Bazzite Deck NVIDIA (immutable, composefs) |
| **vCPUs** | 7 |
| **RAM** | 28 GB |
| **Disk** | 1 TB (virtio) |
| **GPU** | NVIDIA RTX 2070 (full passthrough) |
| **Boot mode** | Boots into Steam Big Picture (Game Mode via gamescope) |
| **Network** | Bridged LAN (DHCP) + Tailscale (stable IP) |

## GPU Passthrough Setup

The RTX 2070 is the **only GPU** in the host machine. When the VM starts, the host console goes completely black (no display output). Manage the host via SSH or Proxmox web UI from another machine.

### Host Configuration

**GRUB** (`/etc/default/grub`):
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```

**VFIO binding** (`/etc/modprobe.d/vfio.conf`):
```
options vfio-pci ids=10de:XXXX,10de:XXXX,10de:XXXX,10de:XXXX
```

All four PCI functions of the GPU (video, audio, USB, serial) must be bound to vfio-pci.

**Blacklist host drivers** (`/etc/modprobe.d/blacklist-nvidia.conf`):
```
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
```

**Load VFIO modules** (`/etc/modules-load.d/vfio.conf`):
```
vfio
vfio_iommu_type1
vfio_pci
```

After any changes:
```bash
update-initramfs -u -k all && update-grub && reboot
```

### Proxmox VM Config

Key settings in the VM configuration:
- Machine type: `q35`
- BIOS: OVMF (UEFI)
- PCI passthrough: GPU with all functions, `x-vga=1`
- CPU type: `host` (for full feature exposure)

---

## Game Streaming (Sunshine / Moonlight)

Stream games from the VM to any device running Moonlight (phone, tablet, another PC, Steam Deck).

### Architecture

```
gamescope (virtual display compositor)
  └── Steam Big Picture (Game Mode)
        └── Sunshine (KMS capture → NVENC encode → stream)
              └── Moonlight client (decode + display)
```

### Critical: KMS Capture Only

**NEVER use `capture=x11`** on this setup. The gamescope Xwayland root framebuffer is black even while games render correctly. X11 capture results in a black screen with only a cursor visible.

**Always use `capture=kms`**, which captures directly from the DRM/KMS layer where the actual rendered frames exist.

### Services

| Service | Purpose |
|---------|---------|
| `gamescope-session-plus@steam.service` | Virtual display compositor + Steam |
| `sunshine-live.service` | Watchdog that launches Sunshine with `capture=kms` |
| `sunshine-health-check.timer` | Auto-recovery every 60s |

### Sunshine Config

```ini
# ~/.config/sunshine/sunshine.conf
capture = kms
encoder = nvenc
adapter_name = /dev/dri/card0
```

### Watchdog Script

The watchdog (`~/bin/sunshine-watchdog.sh`):
1. Waits for gamescope socket to be ready
2. Waits for DRM connector to be enabled with DPMS on
3. Launches `/usr/bin/sunshine capture=kms` in a loop
4. Restarts Sunshine if it crashes

### Health Check Script

The health check (`~/.local/bin/sunshine-health-check.sh`):
1. Verifies Sunshine is running with KMS capture (not X11)
2. Checks DRM connector status (enabled + DPMS on)
3. Checks Sunshine ports are listening
4. Full stack recovery if anything is wrong

### Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `503 failed to initialize video capture` | Display off / DPMS / connector disabled | Health check auto-recovers |
| Black screen + cursor | Wrong capture backend (X11) | Force `capture=kms` everywhere |
| No NVENC | GPU not ready / wrong driver | Check `nvidia-smi`, restart gamescope |

### Codec Support

- **H.264**: Yes (NVENC)
- **HEVC**: Yes (NVENC)
- **AV1**: No (RTX 2070 doesn't support AV1 encode)

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 47984 | TCP | Control |
| 47989 | UDP | Video stream |
| 48010 | TCP | RTSP |

---

## Bazzite OS Notes

- **Immutable filesystem**: Root `/` always shows 100% disk usage (composefs). Check `/var/home` for actual usage.
- **Package management**: Use `rpm-ostree` for system packages, Flatpak for GUI apps, `brew` for CLI tools.
- **Emulators**: Dolphin, PCSX2, RPCS3, RetroArch, Cemu, Ryujinx, Lutris — all installed as Flatpaks.

---

## Verification Commands

```bash
# Check Sunshine is using KMS capture
pgrep -af '/usr/bin/sunshine'   # should show capture=kms

# Check service status
systemctl --user status sunshine-live.service gamescope-session-plus@steam.service

# Check DRM connectors
for d in /sys/class/drm/card*-*; do
  [ -f "$d/status" ] || continue
  [ "$(cat "$d/status")" = connected ] || continue
  echo "$d status=$(cat $d/status) enabled=$(cat $d/enabled) dpms=$(cat $d/dpms)"
done

# Check Sunshine logs (good state shows "Screencasting with KMS")
grep -E 'Screencasting with|Found monitor' /tmp/sunshine.log | tail -10
```
