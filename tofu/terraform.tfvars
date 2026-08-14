proxmox_endpoint = "https://192.168.1.200:8006/"
proxmox_insecure = true

target_node    = "pve"
template_vm_id = 9000
bridge         = "vmbr0"

ci_user = "ubuntu"

ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINgcvAvT5YBBNQ61G9DGgHr+8yXC67UHWbXySuk918uZ ansible-control"

# Permanent control-plane VMs. Keep empty in the sanitized/public repo.
# The zero-to-lab script can generate a private control-vm.auto.tfvars.json
# for VM101 ansible-control during a clean-install rehearsal.
#
# control_vms = {
#   ansible-control = {
#     vm_id     = 101
#     cpu_cores = 2
#     memory_mb = 2048
#     disk_gb   = 20
#     ip_cidr   = "192.168.1.211/24"
#     gateway   = "192.168.1.1"
#     cpu_type  = "x86-64-v2"
#   }
# }
control_vms = {}

dev_vms = {
  dev-00 = {
    vm_id         = 110
    cpu_cores     = 5
    memory_mb     = 8192
    disk_gb       = 80
    ip_cidr       = "192.168.1.110/24"
    gateway       = "192.168.1.1"
    ansible_group = "dev"
  }
  dev-01 = {
    vm_id         = 111
    cpu_cores     = 5
    memory_mb     = 8192
    disk_gb       = 80
    ip_cidr       = "192.168.1.111/24"
    gateway       = "192.168.1.1"
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

# Tailscale utility LXC containers.
# Production currently has VMID 100 `mltailscale` as a Debian 12 LXC with
# `/dev/net/tun` access and advertised subnet route `192.168.2.0/24`.
# Keep this empty in the sanitized/public repo. Put real values in the private
# execution copy only, for example:
#
# tailscale_lxcs = {
#   mltailscale = {
#     vm_id            = 100
#     cpu_cores        = 1
#     memory_mb        = 1024
#     swap_mb          = 1024
#     disk_gb          = 8
#     ip_cidr          = "192.168.1.100/24"
#     gateway          = "192.168.1.1"
#     datastore_id     = "local-lvm"
#     template_file_id = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
#     ostype           = "debian"
#     unprivileged           = false
#     # Keep false when using an API token. Root-only TUN/feature config is applied by ansible/site-tailscale-lxc-host.yml.
#     enable_tun_passthrough = false
#   }
# }
tailscale_lxcs = {}
