# After provisioning the box, complete the install manually via the booted GUI
# Then complete configuration at the web GUI at https://192.168.0.107:8007/

terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_vm_qemu" "proxmox-backup-server" {
  target_node = var.proxmox_host_node
  sockets = 1
  onboot = true
  ipconfig0 = "[gw=192.168.0.1, ip=192.168.0.107/24]"
  network {
    model = "virtio"
    bridge = var.config_network_bridge
  }
  disks {
    ide {
      ide2 {
        cdrom {
          iso = var.iso_image_location
        }
      }
    }
    virtio {
      virtio0 {
        disk {
          size = var.boot_disk_size
          storage = var.boot_disk_storage_pool
          backup = true
        }
      }
      virtio1 {
        disk {
          size = var.backup_disk_size
          storage = var.backup_disk_storage_pool
          backup = true
        }
      }
    }
  }
}

resource "proxmox_virtual_environment_container" "ubuntu_container" {
  description = "Runs backups of Proxmox containers and VMs."

  node_name = "Proxmox Backup Server (PBS)"
  vm_id = 113

  initialization {
    hostname = "terraform-provider-proxmox-ubuntu-container"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  network_interface {
    name = "veth0"
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.proxmox-backup-server.id
    type = "debian"
  }

  mount_point {
    # bind mount, *requires* root@pam authentication
    volume = "/mnt/bindmounts/shared"
    path = "/mnt/shared"
  }

  mount_point {
    # volume mount, a new volume will be created by PVE
    volume = "local-lvm"
    size = "10G"
    path = "/mnt/volume"
  }
}

resource "proxmox_virtual_environment_download_file" "proxmox-backup-server" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name = "first-node"
  url = "https://enterprise.proxmox.com/iso/proxmox-backup-server_3.3-1.iso"
}
