# Terraform — LXC/VM Shell Provisioning

Infrastructure-as-code for the Proxmox cluster, using the
[`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox) provider.

## Scope (read this first)

Terraform here manages the **container/VM envelopes only** — the LXC and VM
*shells*: which node they live on, cores, memory, disk size, swap, hostname,
network bridge, and feature flags (nesting/keyctl). That's it.

It deliberately does **not** manage anything *inside* the guest:

| Managed by Terraform | **Not** managed by Terraform |
|----------------------|------------------------------|
| Node placement, cores, memory, disk, swap | Installed packages / app software → **Ansible** |
| Hostname, network bridge, nesting/keyctl | App data + configs → **restic** restore |
| The VM/LXC existing at all | GPU passthrough cgroup/mount lines (provider can't express them) → manual |
| | Tailscale auth, Ollama model pulls, service start → **Ansible / manual** |

Every resource carries `lifecycle { ignore_changes = all }`. The config is
**documentation + disaster-recovery shell-recreation**, not a live reconciler:
it won't fight manual changes made in the Proxmox UI, and a stray `apply` won't
clobber a running guest. Convergence of in-guest state is the **Ansible**
layer's job (see [`../ansible/`](../ansible)); full recovery is
Terraform **+** Ansible **+** restic **+** a few manual steps, as laid out in
[Disaster Recovery](../docs/disaster-recovery.md).

## Layout

| File | Purpose |
|------|---------|
| `main.tf` | Provider + backend config |
| `variables.tf` | Input variables (endpoint, token, password, ssh key) |
| `containers.tf` | AIServer LXCs (100/101/102/103/104/105) + MediaServer LXC 200 |
| `vms.tf` | Bazzite gaming VM template (commented — its node was decommissioned) |
| `outputs.tf` | Container map + cluster node list |
| `.terraform.lock.hcl` | Provider version lock |
| `terraform.tfvars.example` | Template for your secrets — copy to `terraform.tfvars` |

## Usage

```bash
# 1. Supply your secrets (gitignored).
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# 2. Initialise the provider.
terraform init

# 3. Import existing guests (don't recreate live ones from scratch).
terraform import 'proxmox_virtual_environment_container.aiserver["100"]' AIServer/lxc/100
terraform import proxmox_virtual_environment_container.docker_server MediaServer/lxc/200
# ...repeat per guest...

# 4. Validate / plan.
terraform validate
terraform plan
```

Because of `ignore_changes = all`, a plan against already-imported guests is a
no-op — exactly what you want for a documentation/DR config. To genuinely
recreate a lost shell, remove it from state (or start from an empty state) and
`terraform apply`.

## Secrets

Nothing sensitive lives in this directory. `terraform.tfstate*` and
`terraform.tfvars` are gitignored. The `proxmox_api_token` and `root_password`
variables are marked `sensitive` and have **no defaults** — they must be
supplied via `terraform.tfvars` (or `TF_VAR_*` env vars).
