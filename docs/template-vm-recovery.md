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

### Rehearsed fallback build procedure
These commands were validated on `proxmox-rulab` for an Ubuntu 22.04 cloud-image template and then revised to align the lab template hardware profile with the original production template.

Use an image-capable storage backend for both the imported disk and cloud-init drive. On the rehearsal host, `local` supports only `iso,vztmpl,backup`, so `local:cloudinit` is wrong; use `local-lvm` for imported disks and cloud-init media.

Original production template hardware profile observed for VM `9000`:
- BIOS: `ovmf`
- machine: `q35`
- CPU: `x86-64-v2-AES`
- SCSI controller: `virtio-scsi-single`
- EFI disk: `efidisk0`, 4M
- root disk: `scsi0`, `iothread=1`, about 20G
- cloud-init media: `scsi1`
- placeholder `ide2: none,media=cdrom`
- boot order: `ide2;net0;scsi0`
- network: `virtio`, `bridge=vmbr0`, `firewall=1`
- IP config: `dhcp, ip6=dhcp`
- `sockets: 1`, `numa: 0`

CPU caveat from `proxmox-rulab`: the lab host is an old Intel i3-2100 and cannot start VMs with `x86-64-v2-AES`; QEMU failed with `Host doesn't support requested features`. For this lab only, use the closest runnable profile `x86-64-v2` and record the mismatch. On newer/replacement hardware that supports AES, prefer the production value `x86-64-v2-AES`.

```bash
# On the Proxmox host.
set -euo pipefail

VMID=9000
NAME=ubuntu-22-template
IMG_DIR=/var/lib/vz/template/iso
IMG_NAME=ubuntu-22.04-server-cloudimg-amd64.img
IMG_PATH="$IMG_DIR/$IMG_NAME"
IMG_URL=https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
SSH_PUBKEY_FILE=/root/local-access.pub
CPU_MODEL=x86-64-v2-AES   # use x86-64-v2 only on old lab hardware that lacks AES support

mkdir -p "$IMG_DIR"
[ -s "$IMG_PATH" ] || curl -fL "$IMG_URL" -o "$IMG_PATH"

qm destroy "$VMID" --purge 1 --destroy-unreferenced-disks 1 2>/dev/null || true
qm create "$VMID" \
  --name "$NAME" \
  --memory 2048 \
  --cores 2 \
  --sockets 1 \
  --cpu "$CPU_MODEL" \
  --numa 0 \
  --net0 virtio,bridge=vmbr0,firewall=1 \
  --scsihw virtio-scsi-single \
  --ostype l26 \
  --agent 1 \
  --bios ovmf \
  --machine q35

# Proxmox 9 accepted ms-cert=2023 in the audited source config; Proxmox 8.4 did not.
# If ms-cert is unsupported, retry without it.
qm set "$VMID" --efidisk0 local-lvm:0,efitype=4m,ms-cert=2023,pre-enrolled-keys=1 || \
  qm set "$VMID" --efidisk0 local-lvm:0,efitype=4m,pre-enrolled-keys=1

qm importdisk "$VMID" "$IMG_PATH" local-lvm
qm set "$VMID" --scsi0 local-lvm:vm-${VMID}-disk-1,iothread=1
qm resize "$VMID" scsi0 20G
qm set "$VMID" --scsi1 local-lvm:cloudinit
qm set "$VMID" --ide2 none,media=cdrom
qm set "$VMID" --boot 'order=ide2;net0;scsi0'
qm set "$VMID" --ciuser ubuntu
qm set "$VMID" --ipconfig0 ip=dhcp,ip6=dhcp
qm set "$VMID" --sshkeys "$SSH_PUBKEY_FILE"
qm template "$VMID"
qm config "$VMID"
```

### Rehearsed test clone validation
Do not boot the clone before resizing its disk. The imported Ubuntu cloud-image root disk is very small; if a clone boots and cloud-init starts package work before resize, the rehearsal can fail with `OSError: [Errno 28] No space left on device`.

```bash
# On the Proxmox host.
set -euo pipefail

TEMPLATE_VMID=9000
PROBE_VMID=9010
PROBE_NAME=template-probe
SSH_PUBKEY_FILE=/root/local-access.pub

qm destroy "$PROBE_VMID" --purge 1 --destroy-unreferenced-disks 1 2>/dev/null || true
qm clone "$TEMPLATE_VMID" "$PROBE_VMID" --name "$PROBE_NAME" --full 1
qm set "$PROBE_VMID" --ciuser ubuntu
qm set "$PROBE_VMID" --sshkeys "$SSH_PUBKEY_FILE"
qm set "$PROBE_VMID" --ipconfig0 ip=192.168.1.210/24,gw=192.168.1.1,ip6=dhcp
qm resize "$PROBE_VMID" scsi0 20G
qm start "$PROBE_VMID"

# Host-side validation after qemu-guest-agent is installed and active in the guest.
qm agent "$PROBE_VMID" ping
qm agent "$PROBE_VMID" network-get-interfaces
```

From the operator machine connected through the VPN/subnet route, validate the externally reachable address, not the host-side bridge address if that address collides with another LAN device:

```bash
ssh -i <private-key> ubuntu@192.168.2.210 'hostname && id && systemctl is-active qemu-guest-agent && df -h /'
```

Observed mapping during rehearsal:
- guest internal address on `vmbr0`: `192.168.1.210/24`
- operator/VPN reachable address: `192.168.2.210`
- `192.168.1.210` from the operator machine reached a different Debian SSH host, so it was not a valid external verification address.

### If the cloud image lacks QEMU guest agent
Stock cloud images may not have `qemu-guest-agent` installed. During rehearsal, the successful fix was to install it in the guest before treating the clone/template as validated.

For a throwaway probe VM, this can be done via offline chroot from the Proxmox host after stopping the VM. For a reusable template, prefer baking the package into the template before `qm template`.

Required package/service checks:

```bash
# Inside the guest or via a controlled chroot.
apt-get update
apt-get install -y qemu-guest-agent
systemctl enable qemu-guest-agent || true
systemctl is-active qemu-guest-agent
```


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

## Known remaining gaps
- The exact reusable/golden-template baking path still needs to be decided:
  - bake `qemu-guest-agent` into the base template before conversion, or
  - install it during first-boot configuration with Ansible/cloud-init.
- The current rehearsal proof used a throwaway VM 9010 plus offline chroot repair; promote only the clean, reproducible parts into the final template procedure.
