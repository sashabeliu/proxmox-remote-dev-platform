# ansible-control Bootstrap and OpenTofu / Ansible Recovery

## Purpose
Recover the manually managed control VM that acts as the provisioning and configuration entry point.

## Current known target
Observed during audit:
- VM ID: `101`
- name: `ansible-control`
- role: provisioning coordination and configuration entry point

Observed live paths on the control VM:
- OpenTofu: `~/infra/tofu`
- Ansible: `~/infra-ansible`
- helper scripts: `~/infra/scripts`

Tracked assumptions that still matter:
- Ansible inventory expects SSH key path `/home/ubuntu/.ssh/ansible_ed25519`
- generated inventory expects `ansible_user=ubuntu`
- `scripts/render_inventory.py` currently assumes:
  - `/home/ubuntu/infra/tofu`
  - `/home/ubuntu/infra-ansible/inventory/hosts.ini`
- `scripts/provision_all.sh` currently assumes:
  - `$HOME/infra/tofu`
  - `$HOME/infra-ansible`
  - `$HOME/infra/scripts`

## Important current limitation
The repo now lives as a monorepo, but some helper scripts still expect the old split layout from the live control VM.
That means recovery today has two choices:
1. run commands manually from the monorepo, or
2. recreate compatibility paths for the legacy helper scripts

## Minimum required tools on the control VM
The repo assumes the control VM has working access to:
- `git`
- `python3`
- `ssh`
- `ansible-playbook`
- `tofu`

### Rehearsed package installation commands
These commands were validated on the `proxmox-rulab` rehearsal `ansible-control` VM.

```bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y \
  qemu-guest-agent \
  git \
  python3 \
  python3-pip \
  python3-venv \
  ansible \
  curl \
  ca-certificates \
  unzip \
  jq \
  gnupg \
  lsb-release \
  openssh-client

sudo systemctl enable --now qemu-guest-agent || true

if ! command -v tofu >/dev/null 2>&1; then
  VERSION=$(curl -fsSL https://api.github.com/repos/opentofu/opentofu/releases/latest | jq -r .tag_name | sed 's/^v//')
  TMP=$(mktemp -d)
  cd "$TMP"
  curl -fL "https://github.com/opentofu/opentofu/releases/download/v${VERSION}/tofu_${VERSION}_linux_amd64.zip" -o tofu.zip
  unzip -q tofu.zip
  sudo install -m 0755 tofu /usr/local/bin/tofu
  cd /tmp
  rm -rf "$TMP"
fi
```

Observed validated versions during rehearsal:
- `git version 2.34.1`
- `Python 3.10.12`
- `pip 22.0.2`
- `ansible 2.10.8`
- `ansible-playbook 2.10.8`
- `OpenTofu v1.12.5`


## Recommended operator pattern
- keep one safe/public repo clone as the source of truth
- keep one private local `site.yml` outside git
- let the zero-to-lab handoff generate a materialized execution directory on VM101 when needed

Current paths:
- public/source clone on external runner: `/home/alexander/proxmox-remote-dev-platform`
- local private config on external runner: `~/.config/proxmox-remote-dev-platform/site.yml`
- generated VM101 execution directory: `/home/ubuntu/proxmox-remote-dev-platform-private`

The VM101 directory keeps the historical `-private` suffix for compatibility, but it is not a separately maintained duplicate repo.

## Bootstrap steps
1. Recreate the control VM and ensure SSH access as `ubuntu`.
2. Install the required tooling listed above, or let `scripts/rebuild_from_zero_lab.sh --create-control-vm --handoff-to-control` do it.
3. Restore `/home/ubuntu/.ssh/ansible_ed25519` with correct permissions.
4. From the external runner, use the public repo plus `~/.config/proxmox-remote-dev-platform/site.yml`.
5. Run `scripts/rebuild_from_zero_lab.sh --config ... --handoff-to-control` so runtime files are materialized and copied to VM101.
6. Run deploy validation in the VM101 execution directory.
7. Either run commands manually from that execution directory or create compatibility symlinks for the legacy helpers.

### Rehearsed VM creation notes
Validated on `proxmox-rulab` after aligning the lab template to the original production template profile:
- VMID `101`
- name `ansible-control`
- clone source `9000` / `ubuntu-22-template`
- BIOS `ovmf`
- machine `q35`
- SCSI controller `virtio-scsi-single`
- EFI disk present
- 2 CPU cores, 1 socket, NUMA off
- production CPU target: `x86-64-v2-AES`; lab fallback: `x86-64-v2` because the i3-2100 rehearsal host lacks AES support for that QEMU model
- 2048 MB RAM
- 20G root disk on `scsi0` with `iothread=1`
- cloud-init media on `scsi1`
- boot order `ide2;net0;scsi0`
- network `virtio,bridge=vmbr0,firewall=1`
- `onboot: 1`
- internal bridge IP `192.168.1.211/24`
- operator/VPN reachable IP `192.168.2.211`

Do not assume `192.168.1.101` or `192.168.2.101` are available in the rehearsal lab. They were already in use during validation, so VMID `101` was kept while the rehearsal IP was moved to `.211`.

Rehearsed command pattern:
```bash
# On the Proxmox host, after template 9000 exists.
set -euo pipefail

VMID=101
TEMPLATE=9000
NAME=ansible-control
SSH_PUBKEY_FILE=/root/local-access.pub
CPU_MODEL=x86-64-v2-AES   # use x86-64-v2 only on old lab hardware that lacks AES support

qm destroy "$VMID" --purge 1 --destroy-unreferenced-disks 1 2>/dev/null || true
qm clone "$TEMPLATE" "$VMID" --name "$NAME" --full 1
qm set "$VMID" \
  --memory 2048 \
  --cores 2 \
  --sockets 1 \
  --cpu "$CPU_MODEL" \
  --numa 0 \
  --agent 1 \
  --onboot 1 \
  --net0 virtio,bridge=vmbr0,firewall=1 \
  --ipconfig0 ip=192.168.1.211/24,gw=192.168.1.1,ip6=dhcp \
  --ciuser ubuntu \
  --sshkeys "$SSH_PUBKEY_FILE"
qm set "$VMID" --boot 'order=ide2;net0;scsi0'
qm cloudinit update "$VMID"
qm start "$VMID"
qm config "$VMID"
```

Observed aligned rehearsal result:
- VM `101` booted and SSH login succeeded as `ubuntu@192.168.2.211`
- root filesystem: `/dev/sda1`, `20G`, about `17G` free after package/tool install
- Proxmox-side guest-agent check succeeded after installing `qemu-guest-agent`

## Compatibility symlink option
If you want legacy helper scripts to work without editing them, point the old paths at the generated VM101 execution directory.

Validated commands:
```bash
mkdir -p /home/ubuntu/infra
ln -sfn /home/ubuntu/proxmox-remote-dev-platform-private/tofu /home/ubuntu/infra/tofu
ln -sfn /home/ubuntu/proxmox-remote-dev-platform-private/scripts /home/ubuntu/infra/scripts
ln -sfn /home/ubuntu/proxmox-remote-dev-platform-private/ansible /home/ubuntu/infra-ansible
```

## Secret materialization
Preferred current flow from the external runner:

```bash
cd /home/alexander/proxmox-remote-dev-platform
bash scripts/rebuild_from_zero_lab.sh \
  --config ~/.config/proxmox-remote-dev-platform/site.yml \
  --apply \
  --create-control-vm \
  --handoff-to-control
```

Manual materialization, if you intentionally copied `site.yml` onto the runner and are already inside an execution directory:

```bash
python3 scripts/materialize_site_config.py \
  --config ~/.config/proxmox-remote-dev-platform/site.yml \
  --repo-root "$PWD"
bash scripts/validate_repo_safety.sh --mode deploy
```

Legacy private-bundle materialization remains available only for old runbooks:

```bash
bash scripts/materialize_private_config.sh --bundle-root <private-bundle-root>
bash scripts/validate_repo_safety.sh --mode deploy
```

### Historical rehearsal: key and private bundle restore
Validated on the `proxmox-rulab` rehearsal `ansible-control` VM. Do not paste or log key/bundle contents; record only paths, ownership, permissions, and validator output.

Approved restore inputs used during rehearsal:
- local private key source: `/c/Users/Alexander/.ssh/ansible_ed25519`
- local private bundle source: `/c/Users/Alexander/materialize-test-real-4/private-bundle-parent/proxmox-remote-dev-platform`
- target VM/user: `ubuntu@192.168.2.211`
- target private key path: `/home/ubuntu/.ssh/ansible_ed25519`
- target private bundle path: `/home/ubuntu/private-bundle-parent/proxmox-remote-dev-platform`
- target execution directory: `/home/ubuntu/proxmox-remote-dev-platform-private`

Rehearsed commands, with secret values kept external:
```bash
# Copy the approved private SSH key, then lock down permissions.
scp /path/to/ansible_ed25519 ubuntu@<ansible-control-ip>:/home/ubuntu/.ssh/ansible_ed25519
ssh ubuntu@<ansible-control-ip> '
  chmod 700 /home/ubuntu/.ssh
  chmod 600 /home/ubuntu/.ssh/ansible_ed25519
  ssh-keygen -y -f /home/ubuntu/.ssh/ansible_ed25519 > /home/ubuntu/.ssh/ansible_ed25519.pub
  chmod 644 /home/ubuntu/.ssh/ansible_ed25519.pub
'

# Transfer the approved private bundle without printing its contents.
tar -C /path/to/private-bundle-parent -czf - proxmox-remote-dev-platform |
  ssh ubuntu@<ansible-control-ip> '
    umask 077
    install -d -m 700 /home/ubuntu/private-bundle-parent
    tar -C /home/ubuntu/private-bundle-parent -xzf -
    find /home/ubuntu/private-bundle-parent/proxmox-remote-dev-platform -type d -exec chmod 700 {} +
    find /home/ubuntu/private-bundle-parent/proxmox-remote-dev-platform -type f -exec chmod 600 {} +
  '

# Legacy: materialize the execution directory from a private bundle and validate deploy mode.
ssh ubuntu@<ansible-control-ip> '
  cd /home/ubuntu/proxmox-remote-dev-platform-private
  bash scripts/materialize_private_config.sh --bundle-root /home/ubuntu/private-bundle-parent/proxmox-remote-dev-platform
  bash scripts/validate_repo_safety.sh --mode deploy
'
```

Observed rehearsal result:
- `/home/ubuntu/.ssh/ansible_ed25519`: `600 ubuntu:ubuntu`
- `/home/ubuntu/private-bundle-parent`: `700 ubuntu:ubuntu`
- deploy validation passed after materializing all required private files
- execution directory had expected local modifications only in the materialized secret-bearing files

## Manual recovery flow from the materialized execution directory
From the generated VM101 execution directory:
```bash
cd tofu
set -a
. ./proxmox.env
set +a

# If `tofu init` cannot reach registry.opentofu.org, install the pinned provider
# into a temporary filesystem mirror and point TF_CLI_CONFIG_FILE at it.
# This was needed on the rehearsal VM when provider discovery returned 403.
tofu init

tofu validate
tofu plan
# Review the plan before any apply.
tofu apply
python ../scripts/render_inventory.py
cd ../ansible
ansible-playbook -i inventory/proxmox-hosts.ini site-proxmox-hosts.yml
ansible-playbook -i inventory/hosts.ini site.yml
```

### OpenTofu preflight findings from aligned VM 101
Observed on the recreated `ansible-control` VM:
- redacted target inspection showed the materialized `terraform.tfvars` initially pointed at the original endpoint host `192.168.1.200`
- the lab preflight updated the execution directory to use `https://192.168.1.10:8006/`
- a lab-scoped Proxmox API token was created for the rehearsal and materialized into the execution directory without committing it
- `tofu init` could not use `registry.opentofu.org` directly because provider discovery returned `403 Forbidden`
- a temporary filesystem mirror using the pinned `bpg/proxmox` provider version let `tofu init` proceed after backing up/restoring the execution directory lock file
- `tofu validate` passed
- `tofu plan` succeeded with result: `2 to add, 0 to change, 0 to destroy`
- planned resources:
  - `proxmox_virtual_environment_vm.dev["dev-00"]`: VM `110`, 5 cores, 8192 MB RAM, 80G disk, `192.168.1.110/24`
  - `proxmox_virtual_environment_vm.gpu_dev["gpu-dev-01"]`: VM `121`, 16 cores, 16384 MB RAM, 80G disk, `192.168.1.121/24`, `hostpci` mapping `gpu-4070`
- targeted `dev-00` apply was attempted after plan review
- first apply created VM `110` but failed to start it because the lab host allows max 4 vCPUs per VM and the production-shaped `dev-00` requested 5 cores
- a private-only lab override changed `dev-00` to 4 cores
- the materialized `ssh_public_key` was corrected to match `/home/ubuntu/.ssh/ansible_ed25519.pub` by fingerprint
- a later SSH test against `192.168.1.110` still failed because that IP resolved to a different host/MAC than VM `110`; this was a lab IP collision/routing hazard, not a remaining cloud-init key mismatch
- VM `110` was destroyed/recreated for clean proof with private-only lab IP override `192.168.1.212/24`
- final targeted apply completed with `1 added, 0 changed, 0 destroyed`; OpenTofu emitted a non-fatal QEMU guest-agent network-interface warning because the guest agent is not running in the guest
- final VM `110` state: `dev-00`, running, 4 cores, 8192 MB RAM, 80G disk, `192.168.1.212/24`
- SSH from VM 101 to `ubuntu@192.168.1.212` using `/home/ubuntu/.ssh/ansible_ed25519` succeeded
- `cloud-init status --wait` returned `done`, `/dev/sda1` reported about 78G, and `nproc` reported 4
- `qemu-guest-agent` was installed/enabled after first boot; Proxmox-side `qm agent 110 ping` and `qm guest exec 110 -- ...` succeeded
- `scripts/render_inventory.py` rendered `ansible/inventory/hosts.ini` with `dev-00 ansible_host=192.168.1.212` plus static `storage-vm ansible_host=192.168.1.102`
- Ansible connectivity from VM 101 is proven: `ansible -i inventory/hosts.ini dev-00 -m ping` returned `pong`
- Full `site.yml --limit dev-00` from the beginning intentionally remains deferred at the Tailscale/repository boundary for now:
  - the original control VM's Tailscale auth key was recovered and copied without printing it, but it is no longer accepted by Tailscale: `invalid key: API key does not exist`
  - treat long-lived copied Tailscale auth keys as freshness-sensitive; generate a new key for final Tailscale recovery proof
- Recovered original GitHub credentials were copied without printing them and validated by the rehearsal:
  - GitHub deploy-key lookup succeeded
  - GitHub deploy-key registration for the generated `dev-00` Git key succeeded
  - `iris-insight/iris-poc` cloned over SSH into `/home/ubuntu/work/iris-poc`
- Ansible convergence after Tailscale is now proven:
  - `ansible-playbook -i inventory/hosts.ini site.yml --limit dev-00 --start-at-task 'common : Update apt cache'` completed with `ok=42 changed=16 unreachable=0 failed=0 skipped=2`
  - Docker image build/start succeeded and `iris-poc-dev` is running
  - smoke test tasks ran successfully
  - code-server was installed/enabled
  - Docker, Tailscale daemon, and QEMU guest-agent services are active
  - NFS client storage is mounted: `192.168.1.102:/srv/shared` on `/mnt/shared`
- The `git_workspace` role needed an Ansible-version compatibility fix during rehearsal: `accept_newhostkey` is unsupported by Ansible 2.10, so use `accept_hostkey`
- Local private credential copy created outside the public repo at `C:\Users\Alexander\materialize-test-real-4\private-bundle-parent\proxmox-remote-dev-platform\recovered-credentials\original-control-vm.env`

Do not apply the full production-shaped plan on `proxmox-rulab` as-is. The lab host has only 4 CPUs and no PCI mapping for `gpu-4070`; the GPU VM part is expected to fail or overcommit. For lab rehearsal, keep the private-only `dev-00` overrides documented: 4 cores and an unused lab IP such as `192.168.1.212/24`. For the current scope, skip final guest Tailscale join and workload repository setup as documented prerequisites, then focus on the automatic `mltailscale` LXC deployment path in `docs/tailscale-recovery.md` and `docs/guest-tailscale-and-repo-prerequisites.md`.

## Legacy helper flow
If the compatibility paths are in place:
```bash
bash scripts/provision_all.sh
```

## Validation
The control plane recovery is acceptable only when all are true:
- control VM is reachable over SSH
- `tofu` runs successfully
- `ansible-playbook` runs successfully
- `scripts/render_inventory.py` writes the expected inventory
- `/home/ubuntu/.ssh/ansible_ed25519` exists and is usable
- inventory targets can be reached from the control VM

## Known gaps
- control VM creation is still manual/static, not OpenTofu-managed
- OpenTofu state remains a control-plane recovery dependency and must be backed up separately
