provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure
}

resource "proxmox_virtual_environment_vm" "dev" {
  for_each = var.dev_vms

  node_name = var.target_node
  vm_id     = each.value.vm_id
  name      = each.key

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu {
    cores = each.value.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  agent {
    enabled = true
  }

  initialization {
    user_account {
      username = var.ci_user
      keys     = [var.ssh_public_key]
    }

    ip_config {
      ipv4 {
        address = each.value.ip_cidr
        gateway = each.value.gateway
      }
    }
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_gb
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  boot_order = ["scsi0"]
}

resource "proxmox_virtual_environment_vm" "gpu_dev" {
  for_each = var.gpu_dev_vms

  node_name = var.target_node
  vm_id     = each.value.vm_id
  name      = each.key

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu {
    cores = each.value.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  agent {
    enabled = true
  }

  initialization {
    user_account {
      username = var.ci_user
      keys     = [var.ssh_public_key]
    }

    ip_config {
      ipv4 {
        address = each.value.ip_cidr
        gateway = each.value.gateway
      }
    }
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_gb
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  boot_order = ["scsi0"]

  hostpci {
    device  = "hostpci0"
    mapping = "gpu-4070"
    pcie    = true
  }
}
