# =============================================================================
# AIServer LXC Containers
# =============================================================================

locals {
  aiserver_containers = {
    100 = {
      hostname = "media-monitor"
      cores    = 4
      memory   = 8192
      disk     = 20
      swap     = 512
      nesting  = false
      tun      = false
      gpu      = false
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
    }
    102 = {
      hostname = "openclaw"
      cores    = 16
      memory   = 28672
      disk     = 100
      swap     = 512
      nesting  = false
      tun      = false
      gpu      = true # AMD 8060S iGPU passthrough
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
    }
    105 = {
      hostname = "research-env"
      cores    = 16
      memory   = 16384
      disk     = 124
      swap     = 512
      nesting  = true
      tun      = false
      gpu      = true # AMD 8060S iGPU passthrough
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
        address = "dhcp"
      }
    }
  }

  cpu {
    cores = each.value.cores
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
