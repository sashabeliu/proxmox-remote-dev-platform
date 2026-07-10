proxmox_endpoint = "https://192.168.1.200:8006/"
proxmox_insecure = true

target_node    = "pve"
template_vm_id = 9000
bridge         = "vmbr0"

ci_user = "ubuntu"

ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINgcvAvT5YBBNQ61G9DGgHr+8yXC67UHWbXySuk918uZ ansible-control"

dev_vms = {
  dev-00 = {
    vm_id     = 110
    cpu_cores = 5
    memory_mb = 8192
    disk_gb   = 80
    ip_cidr   = "192.168.1.110/24"
    gateway   = "192.168.1.1"
    ansible_group = "dev"
  }
  dev-01 = {
    vm_id     = 111
    cpu_cores = 5
    memory_mb = 8192
    disk_gb   = 80
    ip_cidr   = "192.168.1.111/24"
    gateway   = "192.168.1.1"
    ansible_group = "dev"
  }
}

gpu_dev_vms = {
  gpu-dev-01 = {
    vm_id     = 121
    cpu_cores = 16
    memory_mb = 16384
    disk_gb   = 80
    ip_cidr   = "192.168.1.121/24"
    gateway   = "192.168.1.1"
  }
}
