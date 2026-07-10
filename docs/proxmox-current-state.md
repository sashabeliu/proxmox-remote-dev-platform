# Current Proxmox State (Read-only audit snapshot)

This document is a sanitized snapshot based on a read-only audit. It is not a live export and should be refreshed as the platform evolves.

## Host
- hostname: `pve`
- Proxmox VE: 9.1.1
- Debian base: 13
- kernel observed: `6.17.2-1-pve`
- CPU threads observed: 20
- memory observed: ~31 GiB total

## Storage
- root filesystem on local NVMe
- `local` storage for ISO / templates / backups / import
- `local-lvm` thinpool for VM and container disks
- no ZFS pool observed during audit

## Observed guests

### LXC
- `100` - `mltailscale`

### VMs
- `101` - `ansible-control`
- `102` - `storage-vm`
- `110` - `dev-00`
- `111` - `dev-01`
- `120` - `gpu-dev-00` (stopped during audit)
- `121` - `gpu-dev-01`
- `9000` - `ubuntu-22-template`

## Current automation split

### On `ansible-control`
Provisioning:
- `~/infra/tofu`

Configuration:
- `~/infra-ansible`

### Observed behaviors
- OpenTofu provisions dev and GPU dev VMs
- a helper script renders Ansible inventory from OpenTofu outputs
- Ansible configures guests and selected host behaviors

## Important risk observations
- no Proxmox scheduled backup jobs were observed
- OpenTofu state is stored locally on the VM
- infrastructure directories were not yet in git
- secrets are mixed into live configuration on the control VM
- application repos on guest VMs contain local drift that is not yet captured in this recovery repo
