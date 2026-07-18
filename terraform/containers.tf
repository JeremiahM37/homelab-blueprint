# =============================================================================
# AIServer LXC Containers
# =============================================================================
# Per-container attributes:
#   cores = null  → no --cores limit (Proxmox "unlimited": all host cores)
#   ip    = "dhcp" or a static "CIDR" (example values only — set your own)
#   gw    = gateway for static IPs, "" for DHCP
#
# Transient dev/tooling containers (e.g. scratch build or sandbox-template
# LXCs) are deliberately NOT modeled here — only the long-lived stack is.

locals {
  aiserver_containers = {
    100 = {
      hostname = "homelab-agent" # historical live hostname: media-monitor
      cores    = 4
      memory   = 8192
      disk     = 20
      swap     = 512
      nesting  = false
      tun      = false
      gpu      = false
      ip       = "dhcp"
      gw       = ""
    }
    101 = {
      hostname = "project-env"
      cores    = 4
      memory   = 4096
      disk     = 30
      swap     = 512
      nesting  = false
      tun      = false
      gpu      = false
      ip       = "dhcp"
      gw       = ""
    }
    102 = {
      hostname = "openclaw"
      cores    = 16
      memory   = 45056
      disk     = 140
      swap     = 512
      nesting  = false
      tun      = false
      gpu      = true # AMD 8060S iGPU passthrough
      ip       = "dhcp"
      gw       = ""
    }
    103 = {
      hostname = "valheim" # dedicated game server — static LAN IP
      cores    = 4
      memory   = 6144
      disk     = 20
      swap     = 2048
      nesting  = false
      tun      = false
      gpu      = false
      ip       = "192.168.1.40/24" # example — set your own static IP
      gw       = "192.168.1.1"
    }
    104 = {
      hostname = "work-env"
      cores    = 4
      memory   = 4096
      disk     = 400
      swap     = 4096
      nesting  = true
      tun      = true # Tailscale
      gpu      = false
      ip       = "dhcp"
      gw       = ""
    }
    105 = {
      hostname = "research-env"
      cores    = null # unlimited — all host cores
      memory   = 32768
      disk     = 274
      swap     = 512
      nesting  = true
      tun      = false
      gpu      = true # AMD 8060S iGPU passthrough
      ip       = "dhcp"
      gw       = ""
    }
    # LXC 106 (ai-detector) archived 2026-05-14 — removed from TF state + config.
  }
}

# NOTE: These resources are for documentation and disaster recovery.
# To import existing containers: terraform import 'proxmox_virtual_environment_container.aiserver["100"]' AIServer/lxc/100
# The lxc.cgroup2 and lxc.mount.entry lines for GPU passthrough are NOT natively
# supported by the Terraform provider — they must be added manually post-create
# or via a null_resource provisioner.

resource "proxmox_virtual_environment_container" "aiserver" {
  for_each = local.aiserver_containers

  node_name   = "AIServer"
  vm_id       = tonumber(each.key)
  description = "Managed by Terraform"

  operating_system {
    template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
    type             = "debian"
  }

  initialization {
    hostname = each.value.hostname

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.gw != "" ? each.value.gw : null
      }
    }
  }

  # cores = null → omit the cpu block entirely so Proxmox applies no limit
  dynamic "cpu" {
    for_each = each.value.cores == null ? [] : [each.value.cores]
    content {
      cores = cpu.value
    }
  }

  memory {
    dedicated = each.value.memory
    swap      = each.value.swap
  }

  disk {
    datastore_id = "local-lvm"
    size         = each.value.disk
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  features {
    nesting = each.value.nesting
    keyctl  = each.value.nesting
  }

  unprivileged  = true
  start_on_boot = false

  lifecycle {
    ignore_changes = all # Don't fight manual changes
  }
}

# =============================================================================
# MediaServer LXC 200 (Docker host)
# =============================================================================

resource "proxmox_virtual_environment_container" "docker_server" {
  node_name   = "MediaServer"
  vm_id       = 200
  description = "Main Docker host — all media services"

  operating_system {
    template_file_id = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
    type             = "debian"
  }

  initialization {
    hostname = "docker-server"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  cpu {
    cores = 12
  }

  memory {
    dedicated = 24576
    swap      = 4096
  }

  disk {
    datastore_id = "local-lvm"
    size         = 400
  }

  # mp0 — DAS bind mount: host /mnt/storage into the container at /mnt/storage.
  # Inside the container, /data/media is a symlink to /mnt/storage/media
  # (created by the Ansible docker-host role).
  mount_point {
    volume = "/mnt/storage"
    path   = "/mnt/storage"
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  features {
    nesting = true
    keyctl  = true
  }

  unprivileged  = true
  start_on_boot = true

  lifecycle {
    ignore_changes = all
  }
}
