# Game Pipeline

Automated pipeline that downloads games and ROMs, syncs them to the gaming VM, extracts/installs them, and adds them to the Steam library — all hands-off after the initial search.

---

## Pipeline Overview

```
Search & Download (LXC 200)          Sync & Install (Gaming VM)
┌──────────┐    ┌──────────┐         ┌──────────────┐    ┌───────────┐
│  Gamarr  │───▶│  qBit    │         │ game-sync.sh │───▶│ Auto-     │
│ (search) │    │(download)│         │  (rsync)     │    │ Install   │
└──────────┘    └────┬─────┘         └──────┬───────┘    └─────┬─────┘
                     │                      │                  │
              ┌──────▼──────┐        ┌──────▼───────┐   ┌─────▼──────┐
              │ /games/vault│◀═rsync═│~/Games/vault/ │   │ Steam ROM  │
              │ /roms/{plat}│        │~/Emulation/   │   │ Import     │
              └─────────────┘        └──────────────┘   └────────────┘
```

## Components

### 1. Gamarr (Search + Download Trigger)

Go binary (~15 MB static build) running inside the gluetun VPN container. Supports 24 platforms and 3 search sources:

- **Prowlarr** — Aggregates torrent indexers (for PC repacks, ROMs via torrent)
- **Myrient** — Direct download for verified ROM sets (No-Intro, Redump)
- **Vimm** — Fallback DDL source for retro ROMs

Features: safety scoring for downloads, library management with SQLite, wishlist, Prometheus metrics, download monitoring, 43 automated e2e tests.

Gamarr sends found torrents/magnets to qBittorrent or downloads directly (DDL) for organizing.

### 2. qBittorrent (Download Client)

Downloads torrents through the VPN tunnel. Files land in:

- PC games → `/games/vault/`
- ROMs → `/roms/{platform}/`

### 3. game-sync.sh (Sync to Gaming VM)

Systemd timer runs every 15 minutes on the gaming VM:

```bash
# Simplified flow
rsync from media-server:/games/vault/ → ~/Games/vault/
rsync from media-server:/roms/        → ~/Emulation/roms/

# For each new archive in vault:
#   detect format → extract → install via Wine/umu-run

# Update Steam library
steam-rom-import.py → shortcuts.vdf
```

### 4. Auto-Install (PC Games)

The sync script detects three installer formats and handles each:

| Format | Detection | Install Method |
|--------|-----------|----------------|
| **NSIS** | `data0.bin` present | `umu-run setup.exe /S /D=...` |
| **FreeArc** | `Setup.exe` + `.dxn`/`.ftp` files | `umu-run Setup.exe -o"..." -y` |
| **FitGirl** | `setup.exe` + `fg-*.bin` files | `umu-run setup.exe /VERYSILENT /DIR=...` |

Games install into `~/Games/installed/{prefix}/drive_c/Games/` using Wine prefixes managed by `umu-run`.

### 5. Steam ROM Import

`steam-rom-import.py` writes to Steam's `shortcuts.vdf` to add:

- **ROMs**: Launched via Flatpak emulators (RetroArch, Dolphin, RPCS3, Ryujinx, etc.)
- **PC games**: Launched via `umu-run` with the appropriate Wine prefix

After import, games appear in the Steam library alongside native Steam games — visible in both Desktop and Game Mode.

---

## ROM Sources

### Myrient (Preferred)

Direct DDL from verified ROM sets. No anti-bot protection, reliable downloads.

Platform path patterns:
```
NES:    No-Intro/Nintendo - Nintendo Entertainment System (Headered)/
N64:    No-Intro/Nintendo - Nintendo 64 (BigEndian)/
DS:     No-Intro/Nintendo - Nintendo DS (Decrypted)/
3DS:    No-Intro/Nintendo - Nintendo 3DS (Decrypted)/
```

> **Note**: Myrient does NOT host Switch ROMs. Use torrent indexers for those.

### Torrent Indexers (via Prowlarr)

For content not on Myrient (Switch games, PC repacks). Prowlarr aggregates multiple indexers and provides a unified search API.

> **Tip**: Some indexer seeder counts are inflated. Verify with multiple sources or check actual connected peers in qBittorrent.

---

## Gotchas

- **Vimm.net** has anti-bot JavaScript that can't be bypassed without a real browser. Use Myrient instead.
- **Magnet links from info_hash alone** have no trackers — you need to add announce URLs for peer discovery.
- **qBit share ratio limits** can auto-delete torrents + files before download completes — check ratio settings.
- **DHCP on the gaming VM** means the LAN IP changes on reboot. Use Tailscale IP for stable rsync targets.
- **Bazzite disk** always shows `/` at 100% (composefs/immutable). Check `/var/home` for real usage.
