# Proxmox Host Baseline Recovery

## Purpose
Recover the minimum Proxmox host configuration expected before guest provisioning and guest configuration are run.

## Current known target
Observed during audit:
- hostname: `pve`
- management IP in tracked inventory: `192.168.1.200`
- SSH user in tracked host inventory: `root`
- bridge expected by tracked config: `vmbr0`
- storage names observed: `local`, `local-lvm`

Tracked host inventory:
- `ansible/inventory/proxmox-hosts.ini`
- `ansible/site-proxmox-hosts.yml`

## What the repo currently automates
The host playbook currently targets `[proxmox_hosts]` and runs only one role:
- `proxmox_gpu_host`

That role currently automates GPU passthrough preparation by:
- setting GRUB kernel flags for IOMMU and VFIO
- writing `/etc/modules-load.d/vfio.conf`
- writing `/etc/modprobe.d/vfio.conf`
- blacklisting `nouveau` and `nvidiafb`
- ensuring VFIO loads before `snd_hda_intel`
- rebooting when needed
- validating GPU VGA/audio functions are bound to `vfio-pci`

Tracked GPU-specific assumptions:
- VFIO IDs: `10de:2786,10de:22bc`
- expected PCI functions checked:
  - `01:00.0`
  - `01:00.1`
- OpenTofu GPU mapping name: `gpu-4070`

## Important current limitation
The repo does not yet fully automate the whole base Proxmox host build.
You still need to install Proxmox and establish the initial management network/storage baseline manually.

## Recovery steps
1. Install Proxmox VE on the replacement host.
2. Recreate the management IP, gateway, and bridge baseline.
3. Ensure `vmbr0` and the expected storage names exist.
4. Ensure root SSH access from the control environment works.
5. If GPU passthrough is required, run the host Ansible playbook.
6. Reboot if the host role changes boot-time VFIO settings.
7. Validate host health before provisioning guests.

## Recovery command for the tracked host role
From the configured control environment:
```bash
cd ansible
ansible-playbook -i inventory/proxmox-hosts.ini site-proxmox-hosts.yml
```

## Validation
The host baseline recovery is acceptable only when all are true:
- Proxmox web UI is reachable
- SSH as root works
- `vmbr0` exists
- expected storage names exist
- if GPU passthrough is required, VFIO validation passes
- host is ready for cloning/provisioning guest VMs

## Manual checks
Useful checks after recovery:
- verify bridge and IP settings in the Proxmox UI
- verify `local` and `local-lvm`
- verify the template VM can be stored and cloned as expected
- if GPU passthrough is used, inspect `lspci -nnk -s 01:00.0` and `01:00.1`

## Known gaps
- no exact command-by-command Proxmox install procedure is captured yet
- no codified host backup/restore for Proxmox-specific local state yet
- no scheduled Proxmox backup jobs were observed during audit
