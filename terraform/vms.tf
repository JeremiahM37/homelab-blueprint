# =============================================================================
# Bazzite Gaming VM (was VM 103 on node "pve") — DECOMMISSIONED 2026-06-22
# -----------------------------------------------------------------------------
# The "pve" node was sold and removed from the cluster. The VM below is kept
# COMMENTED OUT as a rebuild template. To recreate on a new node:
#   1. set node_name to the new Proxmox node
#   2. update the GPU `hostpci` id to the new GPU's PCI address (the RTX 2070
#      left with the old machine — find the new id via `lspci -nn | grep VGA`)
#   3. uncomment, `terraform apply`, then re-run the Bazzite/Sunshine setup
#      (documented in docs/gaming-vm.md). Live config snapshot of the old VM
#      was saved before decommission.
# =============================================================================

/*
resource "proxmox_virtual_environment_vm" "bazzite" {
  node_name   = "pve"
  vm_id       = 103
  name        = "gaming-bazzite"
  description = "Bazzite gaming VM — RTX 2070 GPU passthrough, Steam Game Mode"

  bios    = "ovmf"
  machine = "q35"

  cpu {
    cores   = 7
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 28672
    floating  = 0
  }

  efi_disk {
    datastore_id = "local-lvm"
    type         = "4m"
  }

  disk {
    datastore_id = "local-lvm"
    size         = 1024
    interface    = "scsi0"
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  scsi_hardware = "virtio-scsi-single"

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # GPU Passthrough — update id for the new GPU on the new host
  hostpci {
    device = "hostpci0"
    id     = "0000:01:00"
    pcie   = true
    xvga   = true
    rombar = true
  }

  hostpci {
    device = "hostpci1"
    id     = "0000:00:14.0"
    pcie   = true
  }

  vga {
    type = "none"
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  tablet_device = true
  on_boot       = false

  lifecycle {
    ignore_changes = all
  }
}
*/
