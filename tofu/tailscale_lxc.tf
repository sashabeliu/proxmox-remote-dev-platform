resource "proxmox_virtual_environment_container" "tailscale_lxc" {
  for_each = var.tailscale_lxcs

  description = "Managed by OpenTofu: Tailscale utility LXC"
  node_name   = var.target_node
  vm_id       = each.value.vm_id

  started       = true
  start_on_boot = true
  unprivileged  = each.value.unprivileged

  cpu {
    cores = each.value.cpu_cores
  }

  memory {
    dedicated = each.value.memory_mb
    swap      = each.value.swap_mb
  }

  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = each.value.ip_cidr
        gateway = each.value.gateway
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }
  }

  network_interface {
    name     = "eth0"
    bridge   = var.bridge
    firewall = true
  }

  disk {
    datastore_id = each.value.datastore_id
    size         = each.value.disk_gb
  }

  operating_system {
    template_file_id = each.value.template_file_id
    type             = each.value.ostype
  }

  dynamic "device_passthrough" {
    for_each = each.value.enable_tun_passthrough ? [1] : []

    content {
      path = "/dev/net/tun"
      mode = "0666"
    }
  }

  startup {
    order      = "2"
    up_delay   = "10"
    down_delay = "10"
  }

  tags = ["tailscale", "lxc"]
}
