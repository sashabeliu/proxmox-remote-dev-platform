output "dev_vm_names" {
  value = keys(proxmox_virtual_environment_vm.dev)
}

output "dev_vm_ids" {
  value = {
    for k, v in proxmox_virtual_environment_vm.dev : k => v.vm_id
  }
}

/*
output "ansible_hosts" {
  value = {
    for name, cfg in var.dev_vms : name => {
      ip    = split("/", cfg.ip_cidr)[0]
      group = cfg.ansible_group
    }
  }
}
*/

output "ansible_hosts" {
  value = merge(
    {
      for name, vm in proxmox_virtual_environment_vm.dev :
      name => {
        ip    = split("/", var.dev_vms[name].ip_cidr)[0]
        group = "dev"
      }
    },
    {
      for name, vm in proxmox_virtual_environment_vm.gpu_dev :
      name => {
        ip    = split("/", var.gpu_dev_vms[name].ip_cidr)[0]
        group = "gpu_dev"
      }
    }
  )
}
