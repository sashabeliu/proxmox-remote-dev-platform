resource "proxmox_virtual_environment_vm" "control" {
  for_each = var.control_vms

  description = "Managed by OpenTofu: permanent automation/control-plane VM"
  node_name   = var.target_node
  vm_id       = each.value.vm_id
  name        = each.key
  bios        = "ovmf"
  machine     = "q35"

  scsi_hardware   = "virtio-scsi-single"
  keyboard_layout = "en-us"

  lifecycle {
    ignore_changes = [
      clone,
      agent,
      keyboard_layout,
    ]
  }

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu {
    cores = each.value.cpu_cores
    type  = each.value.cpu_type
  }

  memory {
    dedicated = each.value.memory_mb
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = true
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

  boot_order = ["ide2", "net0", "scsi0"]

  tags = ["control", "ansible", "opentofu"]
}
