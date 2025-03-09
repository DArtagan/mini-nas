terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "3.0.1-rc6"
    }
  }
}

locals {
  ipv4 = "192.168.1.10"  # Keep aligned with what's in configuration.nix for at least initial set-up.
}

module "deploy" {
  source = "github.com/nix-community/nixos-anywhere//terraform/all-in-one"

  # when instance id changes, it will trigger a reinstall
  instance_id = "mini-nas"

  nixos_system_attr = ".#nixosConfigurations.mini-nas.config.system.build.toplevel"
  nixos_partitioner_attr = ".#nixosConfigurations.mini-nas.config.system.build.diskoScript"
  nixos_facter_path = "./facter.json"

  target_host = local.ipv4

  #debug_logging = true  # useful if something goes wrong
}

variable "proxmox_api_token_id" {
  description = "The ID of the API token used for authentication with the Proxmox API."
  type = string
  sensitive = true
}

variable "proxmox_api_token_secret" {
  description = "The secret value of the token used for authentication with the Proxmox API."
  type = string
  sensitive = true
}

variable "proxmox_host_node" {
  description = "The name of the proxmox node where the cluster will be deployed"
  type = string
}

variable "proxmox_api_url" {
  description = "The URL for the Proxmox API."
  type = string
}

variable "proxmox_tls_insecure" {
    description = "If the TLS connection is insecure (self-signed). This is usually the case."
    type = bool
    default = true
}

variable "proxmox_debug" {
    description = "If the debug flag should be set when interacting with the Proxmox API."
    type = bool
    default = false
}

variable "public_key" {
  description = "The public key to be put recognized by containers/vms for remote connection."
  type = string
}


# Note: the first time this was run, to set the `args` value, which is a
# root-only setting, the `_api_token` lines above were commented out and
# PM_USER and PM_PASS environment variables were set with root's
# credentials.  Then they're toggled back on afterwards

provider "proxmox" {
  pm_api_url = var.proxmox_api_url
  #pm_api_token_id = var.proxmox_api_token_id
  #pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure = var.proxmox_tls_insecure
  pm_debug = var.proxmox_debug
}

module "proxmox_backup_server" {
  source = "./modules/proxmox_backup_server"
  proxmox_host_node = var.proxmox_host_node
  proxmox_api_url = var.proxmox_api_url
  proxmox_api_token_id = var.proxmox_api_token_id
  proxmox_api_token_secret = var.proxmox_api_token_secret
  iso_image_location = "local:iso/proxmox-backup-server_2.2-1.iso"
  backup_disk_storage_pool = "proxmox_backup_server"
  backup_disk_size = "1000G"
}
