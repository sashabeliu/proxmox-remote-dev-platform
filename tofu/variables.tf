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

variable "control_vms" {
  description = "Permanent control-plane VMs, such as ansible-control. Keep real lab/prod values in private tfvars or generated auto.tfvars."
  type = map(object({
    vm_id     = number
    cpu_cores = number
    memory_mb = number
    disk_gb   = number
    ip_cidr   = string
    gateway   = string
    cpu_type  = optional(string, "host")
  }))
  default = {}
}

variable "dev_vms" {
  type = map(object({
    vm_id         = number
    cpu_cores     = number
    memory_mb     = number
    disk_gb       = number
    ip_cidr       = string
    gateway       = string
    ansible_group = string
  }))
}

variable "gpu_dev_vms" {
  type = map(object({
    vm_id     = number
    cpu_cores = number
    memory_mb = number
    disk_gb   = number
    ip_cidr   = string
    gateway   = string
  }))
  default = {}
}

variable "tailscale_lxcs" {
  description = "Tailscale utility LXC containers, such as the mltailscale subnet-router container. Keep production values in a private tfvars override."
  type = map(object({
    vm_id                  = number
    cpu_cores              = number
    memory_mb              = number
    swap_mb                = number
    disk_gb                = number
    ip_cidr                = string
    gateway                = string
    datastore_id           = string
    template_file_id       = string
    ostype                 = string
    unprivileged           = bool
    enable_tun_passthrough = bool
  }))
  default = {}
}
