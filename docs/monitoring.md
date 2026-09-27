# Monitoring

The Homelab Agent in **LXC 100** runs proactive checks. Prometheus/Grafana store
metrics, Uptime Kuma checks availability, n8n handles selected workflows, and
Homepage/PWA surface information from those existing services.

## Layers

| Layer | Purpose |
|-------|---------|
| Homelab Agent | Five-minute scans, failure memory, repairs and escalation |
| Uptime Kuma | HTTP/TCP availability and notifications |
| n8n | Selected container, indexer, VPN, backup and disk workflows |
| Prometheus | Metrics from node-exporter, cAdvisor and existing service endpoints |
| Grafana | Container history, host/rack views and project analytics |
| Nightly suite | Broader integration checks and a recorded result |
| `verify` | Checks after a change, including actual browser flows |

## Homelab Agent

The historical hostname is `media-monitor`; the service is `homelab-agent` on
port 9106 **inside LXC 100**, not on AIServer's host address.

Its modules are container doctor, source intelligence, import watchdog,
torrent doctor, system monitor, notifications and AI escalation. SQLite stores
failures and attempts; alert fingerprints prevent repeated notifications.

Repair escalates from the small local model and bounded tools to a larger
fixer with backups/audit records, then to coding-agent review. See
[AI Stack](ai-stack.md). Detection cadence is not a guarantee that every failure
can be repaired automatically.

## Storage: monitor what can fill

`/api/system/storage/<node>` has two kinds of data:

- Top-level disk totals describe physical capacity.
- `filesystems` and `tightest` describe the mounted filesystems that can fill.

AIServer once reached 100% on its root LV while the larger NVMe looked mostly
empty. Homepage now displays `tightest.mount`, `tightest.percent` and
`tightest.free_gb`. MediaServer's DAS is also shown separately.

Monitor `/mnt/bulk` and the underlying LVM thin pool independently. A thin LV's
logical size is not reserved physical capacity. The current API's filesystem
inventory must be checked before assuming it includes every new mount.

A missing DAS can resemble many unrelated broken media services. Check the
host mount, btrfs device errors and the LXC bind mount before restarting apps.

## Metrics without unnecessary load

cAdvisor's filesystem scan once walked every container overlay, used its CPU
quota continuously and was repeatedly OOM-killed. Disable the `disk` metric,
use `--docker_only=true`, and match the 60-second housekeeping/scrape cadence.
This avoids repeated expensive scans of writable layers; use `docker system
df -v` for image/build-cache storage when investigating capacity.

Host temperatures come from the existing temp-api's `/metrics`. No second
collector is needed. The physical rack display uses Grafana's `rack-panel`
dashboard at 1024×600, with 14 grid rows and a one-minute refresh.

## Backup monitoring

Check snapshot freshness by **hostname and tags**, not a raw count of snapshots.
Historical or manually named snapshots can age forever beside healthy scheduled
backups. Retired lineages remain useful recovery evidence but should not raise
an active-service alarm.

Homepage shows backup ages for the active AI host, media host and Docker host.
This is a quick view, not proof that every guest or relocated directory is
covered. Monthly Restic checks and trial restores validate the backup pipeline.
See [Disaster Recovery](disaster-recovery.md).

## VPN monitoring

Subscription expiry, tunnel reachability and verified Mullvad egress are three
separate checks. An upstream probe outage must not be reported as a leak.
Provider names from generic IP databases can change with Mullvad's exit hosts;
the in-tunnel Mullvad response is the stronger signal.

## Nightly tests

The nightly timer runs at 5 AM. `/api/assist/nightly-status` reports the date,
pass/fail/warning counts and failing checks. Counts evolve; this repo does not
present an old fixed number as current coverage.

The dashboard refresh preserves failing results. Several old checks still
assume retired models, frontend markup or unavailable sources. Audit their
premises individually rather than hiding failures or treating every stale
assertion as a current outage. A dashboard UI verification passing does not
mean the entire nightly suite is green.

## Browser checks

Check Homepage at phone, desktop and ultrawide widths, all four tabs, chat
open/close and working launch links. Inspect HTTP and HTTPS separately:
certificate trust, Authelia login, mixed content and same-site cookies change
what works. Never test a power button by submitting its confirmation.

Read [Dashboard](dashboard.md) for the layout and update procedure.

## Terminals

| Port | Target |
|------|--------|
| 7681 | AIServer |
| 7682 | LXC 104 work environment |
| 7683 | LXC 105 research |
| 7684 | LXC 102 inference |
| 7685 | LXC 200 Docker |
| 7686 | MediaServer |
| 7689 | LXC 106 development workspace |

Browser links use the secure PWA's `/term/{port}` wrapper. The Term tab also
supports temporary terminals. The sold node's terminal is retired.
