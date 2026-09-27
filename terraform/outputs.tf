output "aiserver_containers" {
  description = "AIServer LXC container IDs and hostnames"
  value = {
    for k, v in local.aiserver_containers : k => v.hostname
  }
}

output "cluster_nodes" {
  description = "Current Proxmox node names; resolve addresses from your own inventory"
  value = {
    MediaServer = "mediaserver"
    AIServer    = "aiserver"
  }
}
