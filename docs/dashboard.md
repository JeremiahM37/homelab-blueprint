# Dashboard

Homepage is the desktop launcher; the Homelab API's React PWA is the mobile
control surface. Both point at the same services. The September 2026 refresh
keeps four Homepage tabs and separates everyday access from detailed operations.

## Layout

| Tab | First things visible | Further down |
|-----|----------------------|--------------|
| Overview | Lectern, Grimoire, Agent Desk, mobile app, capture and Autonomous Workshop | Host health, filesystem usage, backup ages, nightly failures, downloads, VPN, plan usage |
| Media | Video and book libraries | Download tools, game collections and compact movie/show and book/manga browsers |
| Tools | Notes, files and documents | Formwork, issues/PRs and GitHub Analytics, AI tools, productivity, file drop |
| System | Infrastructure tools and terminals | Proxmox console, terminal hub, detailed system stats |

The power control belongs on System. It keeps its explicit confirmation and
server-side consent check. Opening the dashboard must never execute an action.

## Link rules

- Prefer a useful page to a raw JSON endpoint. Widget API URLs and click targets
  serve different purposes.
- Preserve gateway URLs for services whose login is supplied by Authelia.
  A direct port is not an interchangeable replacement for that gateway.
- Use the secure PWA origin for mobile links and `/term/{port}` wrappers.
- A service returning HTTP 200 might still show a login page or broken widget.
  Check the final URL, rendered text, frame errors and actual controls.
- Remove retired launchers, not the archived service data. AI Detector and the
  old gaming node are no longer dashboard destinations.
- A stopped guest is not necessarily obsolete. Valheim is retained as a stopped
  guest; it is not advertised as a running game server.

## Embeds

Open Homepage at `https://homepage.homelab.internal` for the embedded Proxmox
console. Its `Secure; SameSite=Lax` login cookie needs a same-site HTTPS frame.
On the direct HTTP dashboard, show a link instead. The PWA uses a separate
TLS port on its own tailnet hostname for the same reason.

The PWA, file drop and Grafana frames use HTTPS. Movies & Shows and Books &
Manga remain embedded in compact 480px panels. Library artwork is served by
same-origin `/api/covers/{provider}/{id}` endpoints: the API fetches images from
fixed Jellyfin, Audiobookshelf and Kavita backends, authenticates server-side,
and keeps credentials out of browser URLs. An HTTPS frame alone does not fix
HTTP cover art blocked as mixed content.

Issues & PRs and GitHub Analytics also have compact embedded previews.
Analytics uses `/widget/analytics`, a small chart backed by a persisted snapshot
of the shared tracked-repository list. It serves saved results immediately and
refreshes in the background when three hours old, or when **Refresh** is pressed.
A failed update keeps the last successful data and displays a warning; concurrent
requests share one refresh. Reopening a tab does not query GitHub again while
the snapshot is fresh. The widget shows its update time and also works in the PWA.
The full Grafana report remains available by following the title link.

For Homepage's built-in iframe widget:

- Set `loadingStrategy: lazy` and a descriptive `name` (used as its title).
- Set heights in `custom.css`; arbitrary Tailwind `h-[...]` classes are absent
  from the prebuilt Homepage stylesheet.
- Never cap `#inner_wrapper`'s width. It owns the full-screen background and
  scroll area; a cap strands the dashboard on one side of an ultrawide screen.

## Useful measurements

Homepage consumes existing APIs; it does not add a collector.

| Widget | Data that matters |
|--------|-------------------|
| AIServer disk | Physical `total_display` / `free_display`, plus clearly labelled root `tightest.percent` / `tightest.free_gb` |
| Media disk | DAS filesystem usage and free space |
| Backups | Latest backup age for each active host, not total snapshot count |
| Doc RAG | `docs` and `chunks`; old `indexed_docs` fields no longer exist |
| Nightly tests | Passed, failed, warnings and total; retain real failures |
| Mullvad | Account lifetime and verified routing status, treated separately |
| Agent usage | Provider allowances, reset time and stale/unavailable state |

Routine custom API widgets refresh no faster than 30 seconds; disk/backup
widgets use 60 seconds and nightly/VPN results use five minutes. Duplicate
five-second download lists were removed. Visible iframe apps retain their own
refresh behavior.

## Refresh procedure

1. Read the current Homepage files in LXC 200 at `/opt/docker/homepage/config/`.
2. Compare `href`, widget URLs and iframe sources with live Proxmox, Docker and
   API state. Do not copy operational facts out of an old README.
3. Save the exact files locally and off-box; verify restored hashes.
4. Edit `services.yaml`, `settings.yaml`, `bookmarks.yaml`, `widgets.yaml`,
   `custom.css` and `custom.js`. Preserve secrets in place; do not export them
   into this public repository.
5. Check that no other session edited the files since the snapshot, then deploy.
6. Check every tab at phone, desktop and ultrawide widths, keyboard focus,
   chat open/close, link destinations and iframe behavior. Never test shutdown
   by submitting it.
7. Run `verify` in the affected project and retain evidence privately.

For PWA changes, edit `homelab-api/frontend/src/`, build in `frontend/`, then run
`python3 scripts/publish.py` **from that directory**. Publication stamps the
service-worker cache. Do not hand-edit generated `static/app.html`.
