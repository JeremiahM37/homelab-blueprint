# Ansible provisioning scaffold

This is an earlier provisioning scaffold, updated for the two-node inventory.
It is **not a tested full rebuild of the current homelab**. Use the
[recovery guide](../docs/disaster-recovery.md) and verified backups for recovery.

The examples now use DHCP for guest creation, current container sizes, and only
MediaServer/AIServer in the host inventory. LXC 103 is Valheim; the retired
NVIDIA gaming node is absent. The optional NVIDIA role remains as a historical
example. The Homelab Agent runs in LXC 100; the legacy host-agent tasks default
to disabled.

## Scope

| Roles | What they illustrate | What remains manual |
|-------|----------------------|---------------------|
| common, proxmox-lxcs | Packages and container shells | Guest users/SSH bootstrap, Tailscale enrollment, data restoration |
| docker-host, sso, monitoring | Compose, gateway and logging patterns | Full production compose, service data, credentials and current vhosts |
| ollama, gpu-passthrough | Inference and device mapping | Driver compatibility, tested Ollama version and tool-use evaluation |
| aiserver, dev-environment | Service units and development tools | Application source, venvs, current React builds and configuration |
| backups | Nightly Restic patterns | Bulk symlink targets, LXC105 coverage, cold archive and restore testing |

The scaffold does not deploy Grimoire, Lectern, Formwork, Agent Desk's browser
stack, Tailscale HTTPS, or the current Homepage configuration. Guest creation is
not equivalent to installing the guest's workload. The selected
[Compose example](../docker-compose.example.yml) is likewise partial.

## Review and syntax validation

1. Install Ansible with the `community.general` and `ansible.posix` collections.
2. Copy `inventory.example.yml` to the ignored `inventory.yml`; use stable
   Tailscale addresses or MagicDNS names for existing hosts.
3. Supply your own secrets through Ansible Vault. Review all defaults, templates,
   authentication boundaries, mount points and storage capacities.
4. Select an available Proxmox OS template; the example Debian template may no
   longer be downloadable from your installed Proxmox release.
5. Validate without connecting or provisioning:

   ```bash
   ansible-playbook -i inventory.example.yml playbook.yml --syntax-check
   ansible-playbook -i inventory.example.yml playbook.yml --list-tasks
   ```

Tags include `common`, `lxc`, `docker`, `sso`, `monitoring`, `ai`, `aiserver`,
`backups`, `gpu` and `dev`. Review the selected tasks before running a tag
against your own inventory. Syntax validation does not demonstrate that a
fresh deployment works; no provisioning was performed during this refresh.

LXC 200's example mounts the DAS at `/mnt/storage`; restore its `/data/media`
symlink and verify library paths before starting media containers. Two-node
quorum, per-device browser trust and service setup need separate attention.
