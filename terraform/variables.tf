variable "proxmox_endpoint" {
  type        = string
  default     = "https://proxmox.example.lan:8006"
  description = "Proxmox API endpoint (override in terraform.tfvars)"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token — supply via terraform.tfvars (never commit)"
}

variable "root_password" {
  type        = string
  sensitive   = true
  description = "Root/admin password for containers — supply via terraform.tfvars (never commit)"
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "SSH public key for container init"
}
