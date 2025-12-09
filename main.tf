terraform {
  required_version = ">= 1.10.0"
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.73.0"
    }
    sops = {
      source = "carlpett/sops"
      version = "1.1.1"
    }
  }
}

#variable "proxmox_api_token_id" {
#  description = "The ID of the API token used for authentication with the Proxmox API."
#  type = string
#  sensitive = true
#}
#
#variable "proxmox_api_token_secret" {
#  description = "The secret value of the token used for authentication with the Proxmox API."
#  type = string
#  sensitive = true
#}
#
#variable "proxmox_host_node" {
#  description = "The name of the proxmox node where the cluster will be deployed"
#  type = string
#}
#
#variable "proxmox_api_url" {
#  description = "The URL for the Proxmox API."
#  type = string
#}
#
#variable "proxmox_tls_insecure" {
#    description = "If the TLS connection is insecure (self-signed). This is usually the case."
#    type = bool
#    default = true
#}
#
#variable "proxmox_debug" {
#    description = "If the debug flag should be set when interacting with the Proxmox API."
#    type = bool
#    default = false
#}


data "sops_file" "tofu_secrets" {
  source_file = "tofu_secrets.yaml"
}

provider "proxmox" {
  endpoint = "https://192.168.1.11:8006/"
  api_token = data.sops_file.tofu_secrets.data["proxmox_api_token"]
  insecure = true
}

# Note: the first time this was run, to set the `args` value, which is a
# root-only setting, the `_api_token` lines above were commented out and
# PM_USER and PM_PASS environment variables were set with root's
# credentials.  Then they're toggled back on afterwards

resource "proxmox_virtual_environment_group" "admin" {
  group_id = "admin"
  acl {
    path = "/"
    propagate = true
    role_id = "Administrator"
  }
}

resource "proxmox_virtual_environment_user" "will" {
  user_id = "will@pam"
  password = data.sops_file.tofu_secrets.data["user_will_password"]
  groups = [ proxmox_virtual_environment_group.admin.group_id ]
}

# TODO: maybe create a tofu user?

#module "proxmox_backup_server" {
#  source = "./tofu_modules/proxmox_backup_server"
#  backup_disk_storage_pool = "proxmox_backup_server"
#  backup_disk_size = "1000G"
#}
