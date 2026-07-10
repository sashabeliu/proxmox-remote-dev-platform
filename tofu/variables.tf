variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_insecure" {
  type    = bool
  default = true
}

variable "target_node" {
  type = string
}

variable "template_vm_id" {
  type = number
}

variable "bridge" {
  type = string
}

variable "ci_user" {
  type    = string
  default = "ubuntu"
}

variable "ssh_public_key" {
  type = string
}

variable "dev_vms" {
  type = map(object({
    vm_id      = number
    cpu_cores  = number
    memory_mb  = number
    disk_gb    = number
    ip_cidr    = string
    gateway    = string
    ansible_group = string
  }))
}

variable "gpu_dev_vms" {
  type = map(object({
    vm_id      = number
    cpu_cores  = number
    memory_mb  = number
    disk_gb    = number
    ip_cidr    = string
    gateway    = string
  }))
  default = {}
}
