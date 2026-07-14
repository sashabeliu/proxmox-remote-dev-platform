# Template VM Recovery

## Purpose
Recreate or restore the base VM template that OpenTofu clones for dev and GPU dev guests.

## Current known target
Observed during audit:
- template VM ID: `9000`
- template name: `ubuntu-22-template`
- target node in tracked config: `pve`
- bridge in tracked config: `vmbr0`
- guest user in tracked config: `ubuntu`

Tracked dependencies:
- `tofu/terraform.tfvars`
- `tofu/main.tf`
- `tofu/variables.tf`

OpenTofu currently assumes:
- guests are cloned from `template_vm_id`
- cloud-init style guest initialization is available
- guest agent is enabled on cloned VMs

## Recovery options

### Preferred
Restore the template from a backup/export if one exists.

### Fallback
Recreate an equivalent Ubuntu 22 template manually in Proxmox.

## Minimum required template properties
To be usable by the current OpenTofu config, the template must support all of the following:
- Ubuntu 22 base or another image you intentionally switch to
- Proxmox VM template state
- cloud-init capable guest initialization
- bootable Linux guest on Proxmox
- QEMU guest agent available inside the guest
- usable on the intended target node and storage layout

## Operator steps
1. Install or import the base Ubuntu image into Proxmox.
2. Create a VM intended to become the template.
3. Ensure it can boot successfully once before templating.
4. Ensure the guest is prepared for cloud-init style first-boot configuration.
5. Ensure the QEMU guest agent is installed and enabled in the guest.
6. Convert the VM into a Proxmox template.
7. Set the VM ID to `9000`, or update `tofu/terraform.tfvars` if you intentionally use a different ID.
8. Confirm the template lives on the expected node/storage combination used by your recovery target.

## Required repo checks before provisioning
Review these tracked values:
- `tofu/terraform.tfvars`
  - `target_node`
  - `template_vm_id`
  - `bridge`
  - `ci_user`
  - `ssh_public_key`
- `tofu/main.tf`
  - clone source for `dev` and `gpu_dev`
  - guest agent enabled
  - network bridge `vmbr0`
  - boot disk `scsi0`

## Validation
The template recovery is acceptable only when all are true:
- template exists in Proxmox
- template ID matches `template_vm_id` or tracked config was updated intentionally
- a manual test clone is possible in Proxmox
- cloned guest can accept cloud-init username/key/network initialization
- cloned guest comes up with working guest agent support

## Known gap
This repo does not yet contain the exact command-by-command template build procedure or an exported golden image artifact.
If you recreate the template manually, capture the exact steps afterward and add them here.
