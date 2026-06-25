output "aiserver_containers" {
  description = "AIServer LXC container IDs and hostnames"
  value = {
    for k, v in local.aiserver_containers : k => v.hostname
  }
}

output "cluster_nodes" {
  description = "Proxmox cluster nodes (example LAN IPs — set to your own)"
  value = {
    # pve (gaming node) decommissioned 2026-06-22
    MediaServer = "192.168.1.20"
    AIServer    = "192.168.1.30"
  }
}
