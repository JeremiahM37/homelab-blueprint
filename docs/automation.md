# Automation

Automation is split between service-native workflows, a proactive monitoring
agent, selected n8n jobs and coding-agent escalation. The dashboard consumes
those existing APIs rather than adding another scheduler.

## Media and downloads

Jellyseerr sends requests to Sonarr/Radarr; Prowlarr supplies indexers;
qBittorrent downloads through Gluetun; library managers import the results.
Librarr handles books/audiobooks/manga, while Gamarr manages game collections.

Sentinel tracks requests through search, download and library arrival, with
SQLite persistence. Verification queries the destination library for actual
files, durations or pages. A completed torrent is not proof that a usable item
reached the library.

The old Bazzite-to-Steam sync pipeline is retired. See [Media Stack](media-stack.md)
for the current libraries and the archived [Game Pipeline](game-pipeline.md)
for its historical design.

## Homelab Agent

LXC 100 runs five-minute monitoring cycles: container doctor, source
intelligence, import watchdog, torrent doctor, system monitor, notifications
and AI escalation. The hostname `media-monitor` remains from an older version.

Repairs escalate from bounded tools to a larger local-model fixer with backups
and validation, then to coding-agent review. SQLite failure memory records
attempts; notification fingerprints reduce duplicate alerts.

## n8n

The active workflow set covers container health, disk space, indexer health,
*arr health, VPN reachability, stuck downloads, backup status and Librarr
version checks. The Bazzite watchdog was disabled after the gaming node retired.

Operational constraints:

- Use HTTP Request nodes; Code nodes do not provide `fetch()` here.
- Container actions use the Docker socket proxy. It permits selected writes;
  it is not merely a read-only metrics endpoint.
- Keep chains sequential when fan-out/merge timing would race.
- An HTTP response establishes reachability, not correct VPN identity.
- Disk checks must cover the actual filesystem and each intended host.

## Capture and files

The PWA share target and desktop capture page use the same routing:

| Content | Destination |
|---------|-------------|
| Link or note | Grimoire capture inbox |
| General file | Seafile Inbox |
| Document | Paperless |

The server probes destination availability and reports failures. A missing
Linkwarden token once produced empty results that looked successful; empty
lists must not mask failed capture. The service worker ignores non-GET
requests so it cannot swallow a multipart share POST.

File deletion and job application submission remain explicit user actions.
Formwork's automated preparation does not submit applications.

## Backups and archives

Nightly Restic timers back up host configuration, selected guest trees and the
Docker stack to MediaServer's DAS. Retention is seven daily, four weekly and
three monthly snapshots. Monthly repository checks and trial restores provide
evidence beyond a successful backup command.

The cold archive is a separate repository with **no automatic forget/prune**.
Local originals can be removed only after verified archival and restore/hash
checks; receipts retain the exact snapshot and restore path. See
[Disaster Recovery](disaster-recovery.md).

## Guard services and hardware health

- A Gluetun namespace guard repairs dependencies stranded after recreation.
- DAS checks inspect SMART, btrfs device errors, mount state and capacity; scrub
  runs separately.
- Existing temp-api endpoints also provide Prometheus metrics.
- CrowdSec processes container logs; the firewall bouncer runs on MediaServer.
- Nightly integration tests record pass/fail/warning details, not just a green
  dashboard badge.

## Coding-agent workspace

Lectern manages coding-agent sessions, task review and the autonomous workshop.
The workshop has independent usage and storage controls. Completed work,
reports, review evidence and recovery material are retained; deduplicating
identical executable copies is different from deleting workspaces.

Grimoire supplies context and handoffs. Agent Desk provides a shared real browser
for web work requiring the user's sessions. See [AI Stack](ai-stack.md).
