# Disaster Recovery

No single tool rebuilds this homelab. Recover the infrastructure shells,
configuration, application data and access separately, then verify the result.

## Recovery layers

| Layer | Recovers | Does not recover |
|-------|----------|------------------|
| [Terraform](../terraform/) | Selected container envelopes: placement, cores, RAM, disk and network | Application data, full GPU setup, all operational guests |
| [Ansible](../ansible/) | Earlier examples of in-guest configuration | A tested full reconstruction of the current estate |
| Restic | Backed-up host/guest files and Docker state | Excluded media, caches, model blobs and unlisted paths |
| Git repositories | Published source code | Uncommitted work or private runtime state |
| Manual steps | Hardware, network identity, auth, model pulls and service activation | Anything not recorded and checked |

Terraform's `ignore_changes = all` reduces reconciliation of existing resources.
It does **not** make arbitrary applies safe: new or removed resource definitions
can still create or destroy infrastructure. Import existing guests, inspect the
plan, and never use this public example as production state.

## Nightly backup inventory

The encrypted, deduplicated repository is on MediaServer's DAS. Daily timers use
seven daily / four weekly / three monthly retention.

- AIServer: home configuration/source, Proxmox configuration and selected units.
- LXC 200: Docker configuration and application trees under `/opt/docker`.
- MediaServer: host configuration, network and SSH material.
- Selected AIServer guests: per-guest configuration/source archives, including
  the current development workspace and shared browser setup.
- Relocated non-cache project and recovery directories: explicitly included
  from `/mnt/bulk` where needed.

Inspect the backup scripts and actual snapshot paths for exact coverage. Restic
**does not follow directory symlinks**. A directory moved to bulk and symlinked
back into home disappears from a home-only backup unless its real path is added.

Historical gaming-node and AI-detector snapshots are recovery records, not
proof those services are still running. Guest IDs have been reused.

## Cold archive

A separate repository on the DAS holds inactive recovery trees, model/research
outputs and other verified offloaded data. It has no automatic retention
policy: some originals no longer exist locally.

Keep receipts with snapshot ID, original path and restore path. Before
reclaiming a source tree, verify a restore and hashes, check for changes since
backup, and inspect active processes' cwd/open files/mappings. Do not prune this
repository with the nightly policy.

## Restore order

1. Restore MediaServer storage and verify the DAS mount and btrfs health.
2. Restore Proxmox host configuration for the **two current nodes**. Plan quorum
   and network recovery; do not restore the retired host into the active cluster.
3. Recreate or restore guest shells from checked configuration/vzdump archives.
   Review VMID reuse and the current disk sizes before importing any state.
4. Restore files into a staging path first, inspect them and compare expected
   ownership/layout before placing them into service paths.
5. Bring up DNS, Tailscale, storage mounts, databases and application services in
   dependency order. Only the intended Compose profiles should start.
6. Restore GPU device mappings, model files where archived (or pull again),
   service environment files and authentication. Keep credential values private.
7. Check direct endpoints, gateway access, actual browser flows and logs. Run
   the affected project's `verify` suite.

The shared browser contains account sessions; its backups need the same care as
other credentials. Keep it private and restore permissions before starting it.

## Verification and limits

- Test-restored hashes are stronger evidence than “backup completed.”
- Repository freshness and guest coverage are different questions.
- Restic repository permissions must work for each writer, including
  unprivileged LXC mappings. Verify the intended identities rather than blindly
  copying host ownership or weakening permissions.
- Bulk media and re-downloadable model blobs are not assumed backed up.
- A DAS backup is a different-host copy, not an off-site disaster strategy.
- Thin-pool capacity and root filesystem capacity are separate limits. Removing
  a thin guest disk does not free extents in the fixed root LV.
