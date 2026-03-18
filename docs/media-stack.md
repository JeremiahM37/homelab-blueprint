# Media Stack

Automated media management — request content, find it, download it, organize it, serve it.

---

## Pipeline

```
User Request                Search & Download              Organize & Serve
┌───────────┐    ┌─────────┐    ┌───────────┐    ┌─────────┐    ┌──────────┐
│Jellyseerr │───▶│ Sonarr  │───▶│ Prowlarr  │───▶│  qBit   │───▶│ Jellyfin │
│(requests) │    │ Radarr  │    │(indexers) │    │(torrent)│    │(stream)  │
└───────────┘    └────┬────┘    └───────────┘    └────┬────┘    └──────────┘
                      │                               │
                      │         ┌───────────┐         │
                      └────────▶│  Bazarr   │◀────────┘
                                │(subtitles)│
                                └───────────┘
```

## How It Works

1. **Jellyseerr** — Users browse and request movies/TV shows through a clean web UI
2. **Sonarr / Radarr** — Receive requests, search for releases via Prowlarr, send to download client
3. **Prowlarr** — Central indexer manager, searches multiple torrent/usenet indexers
4. **qBittorrent** — Downloads through VPN tunnel (gluetun), auto-extracts via Unpackerr
5. **Sonarr/Radarr** — Import completed downloads, rename files, organize into library structure
6. **Bazarr** — Automatically finds and downloads subtitles for new media
7. **Jellyfin** — Serves the organized library to any device (web, mobile, TV apps)

### Transcoding

- **Tdarr** — Automated batch transcoding of existing library
  - Re-encodes to target codec/bitrate to save space
  - Hardware transcoding via host iGPU (AMD Radeon 780M)
- **Jellyfin** — On-the-fly transcoding for clients that can't direct play
  - Also uses hardware transcoding via iGPU

---

## Book Pipeline

```
┌──────────┐    ┌───────────┐    ┌──────────┐
│ Shelfarr │───▶│ Librarr   │───▶│ qBit /   │
│(wishlist)│    │(search +  │    │ DDL      │
└──────────┘    │ download) │    └────┬─────┘
                └───────────┘         │
                                      ▼
                ┌─────────────────────────────────┐
                │         Organize & Serve         │
                ├──────────┬───────────┬───────────┤
                │Calibre-  │  Kavita   │Audiobook- │
                │Web       │(comics/   │shelf      │
                │(ebooks)  │ manga)    │(audio)    │
                └──────────┴───────────┴───────────┘
```

- **Shelfarr** — Track wanted books, send to Librarr
- **Librarr** — Custom Flask app that searches multiple sources (Anna's Archive, LibGen, Gutenberg, Open Library, Librivox)
- **Post-download**: Organize files → import to appropriate library → track in SQLite

### Book Sources

| Source | Content | Method |
|--------|---------|--------|
| Anna's Archive | Ebooks (epub, pdf) | Direct download via LibGen mirrors |
| LibGen | Ebooks, papers | Direct download |
| Project Gutenberg | Public domain ebooks | Direct download |
| Open Library | Ebook lending | API |
| Librivox | Public domain audiobooks | Direct download |

### Library Servers

| Server | Port | Content |
|--------|------|---------|
| **Calibre-Web** | 8083 | Ebooks (OPDS feed for e-readers) |
| **Kavita** | 5005 | Comics, manga, light novels |
| **Audiobookshelf** | 13378 | Audiobooks, podcasts |

---

## Storage Layout

```
DAS (8 TB btrfs)
└── /mnt/storage/media/
    ├── movies/
    ├── tv/
    ├── music/
    ├── books/
    │   ├── ebooks/
    │   │   └── incoming/     ← qBit downloads here (PUID 1000)
    │   └── audiobooks/       ← qBit downloads here (PUID 1000)
    ├── comics/
    └── ...
```

The DAS is USB-attached to the MediaServer host, mounted at `/mnt/storage`, and bind-mounted into LXC 200 at `/data/media`.

**Critical**: All media services depend on this mount. If the DAS is disconnected, containers will fail to start or crash with I/O errors. Always verify the mount before troubleshooting service issues:

```bash
mountpoint /mnt/storage && ls /mnt/storage/media
```

---

## Permissions

All containers run with PUID/PGID 1000. Download directories **must** be owned by `1000:1000`:

```bash
chown -R 1000:1000 /data/media/books/ebooks/incoming
```

qBittorrent will show "error" state if it can't write to the download directory — this is almost always a permissions issue.

---

## FlareSolverr

Some indexers use Cloudflare protection. FlareSolverr runs a headless browser to solve challenges and passes cookies back to Prowlarr. It's internal-only (no exposed port) and used automatically by Prowlarr when needed.
