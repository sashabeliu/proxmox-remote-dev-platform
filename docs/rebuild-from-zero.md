# Rebuild From Zero: Non-GPU Lab Profile

## Purpose

This document defines the test path from a freshly installed Proxmox host to the current non-GPU lab state:

```text
fresh Proxmox install
-> external runner bootstrap
-> Proxmox host bootstrap
-> Ubuntu template / LXC template readiness
-> VM101 ansible-control creation
-> VM101 control runner tools and private config
-> handoff to VM101
-> VM101 OpenTofu VM/LXC provisioning
-> VM101 Ansible host/guest convergence
-> final verification
```

The lab profile intentionally excludes `gpu-dev-01`.

## Current automation entrypoint

From an external Debian/Ubuntu runner with a public repo clone and one private local site config:

```bash
cd /home/alexander/proxmox-remote-dev-platform
bash scripts/rebuild_from_zero_lab.sh --config ~/.config/proxmox-remote-dev-platform/site.yml
```

Default mode is non-destructive check/plan mode.

The preferred full rebuild is external bootstrap + VM101 handoff:

```bash
bash scripts/rebuild_from_zero_lab.sh \
  --config ~/.config/proxmox-remote-dev-platform/site.yml \
  --apply \
  --create-template \
  --create-control-vm \
  --handoff-to-control
```

In handoff mode, the external runner creates and configures VM101, copies a materialized execution tree to it, then VM101 runs the remaining lab deployment. The VM101 path currently keeps the historical name `/home/ubuntu/proxmox-remote-dev-platform-private`, but it is generated from the public repo plus `site.yml` and is not a separately maintained repo.

To apply the host bootstrap and rebuild the selected lab guests directly from the external runner instead:

```bash
bash scripts/rebuild_from_zero_lab.sh \
  --config ~/.config/proxmox-remote-dev-platform/site.yml \
  --apply \
  --destroy-existing
```

This destroys/recreates only:

```text
VM 110 dev-00
CT 100 tailscale-rulab
```

It does not target:

```text
gpu-dev-01
```

## Fresh-install manual minimum

This script does not yet automate the Proxmox ISO installer itself.

Manual minimum before running automation:

```text
1. Install Proxmox VE from ISO
2. Set hostname
3. Set root password
4. Configure management IP/network/gateway/DNS
5. Ensure root SSH is reachable from the external runner over a path that does not depend on any Proxmox guest/CT
```

Everything after root SSH should be scriptable/testable.

## External runner bootstrap

If the external runner is a fresh Ubuntu/Debian machine, first run:

```bash
bash scripts/bootstrap_control_runner.sh --with-opentofu-provider-mirror
```

This installs:

```text
git
python3
ansible
curl/jq/unzip/gnupg
OpenTofu
optional local bpg/proxmox provider mirror
```

The provider mirror option is useful where `registry.opentofu.org` is blocked or unreliable.

The external runner is intentionally temporary. Its job is to bootstrap Proxmox and recreate VM101. VM101 then becomes the normal permanent control plane.

## Private config materialization

Preferred current input is one local private site config:

```text
~/.config/proxmox-remote-dev-platform/site.yml
```

Create it from the repo template:

```bash
mkdir -p ~/.config/proxmox-remote-dev-platform
cp config/site.example.yml ~/.config/proxmox-remote-dev-platform/site.yml
chmod 600 ~/.config/proxmox-remote-dev-platform/site.yml
nano ~/.config/proxmox-remote-dev-platform/site.yml
```

For a real apply, pass it to the zero script:

```bash
bash scripts/rebuild_from_zero_lab.sh \
  --config ~/.config/proxmox-remote-dev-platform/site.yml \
  --proxmox-host <optional-cli-override>
```

The materializer writes runtime execution files such as:

```text
tofu/proxmox.env
tofu/terraform.tfvars
ansible/group_vars/all.yml
ansible/group_vars/dev.yml
ansible/group_vars/gpu_dev.yml
ansible/group_vars/proxmox_hosts.yml
ansible/group_vars/tailscale_lxc.yml
```

These files replace placeholders with real values in the local execution context. Do not commit them after materialization.

Legacy private-bundle mode remains available through `--private-bundle-root`, but it is no longer the preferred source-of-truth workflow.

## Proxmox host bootstrap

The zero script calls:

```text
ansible/site-proxmox-bootstrap.yml
```

which runs role:

```text
ansible/roles/proxmox_host_base
```

The role verifies or configures:

```text
Proxmox commands exist: pveversion, pvesh, qm, pct, pveam, pvesm, pveum
base packages
optional apt repo policy
root SSH authorized key
/root/local-access.pub for cloud-init/template use
required bridge, default vmbr0
required storage IDs, default local and local-lvm
/dev/net/tun on host
Debian 12 LXC template
optional Ubuntu 22 cloud-image template VM 9000
optional Proxmox API user/token for OpenTofu
```

Host bootstrap only:

```bash
bash scripts/rebuild_from_zero_lab.sh \
  --proxmox-host <host> \
  --skip-lab-profile
```

Host bootstrap check mode:

```bash
bash scripts/rebuild_from_zero_lab.sh \
  --proxmox-host <host> \
  --skip-lab-profile
```

Host bootstrap apply mode:

```bash
bash scripts/rebuild_from_zero_lab.sh \
  --proxmox-host <host> \
  --apply \
  --skip-lab-profile
```

## Optional template creation

To create template VM `9000` if missing:

```bash
bash scripts/rebuild_from_zero_lab.sh \
  --proxmox-host <host> \
  --apply \
  --create-template \
  --skip-lab-profile
```

To deliberately recreate template VM `9000`:

```bash
bash scripts/rebuild_from_zero_lab.sh \
  --proxmox-host <host> \
  --apply \
  --create-template \
  --recreate-template \
  --skip-lab-profile
```

Warning: `--recreate-template` destroys VM/template `9000` first.

The template automation follows the rehearsed Ubuntu 22 cloud-image procedure in `docs/template-vm-recovery.md`.

Known caveat:
- The lab i3-2100 host cannot run `x86-64-v2-AES`.
- The role falls back to `x86-64-v2` if primary CPU model creation fails.

## Optional API token generation

To let the host bootstrap create/check the Proxmox API user/token:

```bash
bash scripts/rebuild_from_zero_lab.sh \
  --proxmox-host <host> \
  --apply \
  --manage-api-token \
  --pull-generated-token \
  --skip-lab-profile
```

If a new token is created, the secret is stored only on the Proxmox host at:

```text
/root/proxmox-api-token.env
```

With `--pull-generated-token`, the script copies it into the current materialized execution context:

```text
tofu/proxmox.env
```

If the token already exists but the env file is missing, the existing secret cannot be recovered. Rotate/recreate deliberately.

## VM101 ansible-control handoff

The clean architecture is:

```text
external runner = bootstrap installer
VM101 ansible-control = permanent control plane
```

To generate the private runtime `tofu/control-vm.auto.tfvars.json`, create VM101, configure it, copy the materialized execution tree there, and hand off the rest of the deployment:

```bash
bash scripts/rebuild_from_zero_lab.sh \
  --proxmox-host <host> \
  --apply \
  --create-template \
  --create-control-vm \
  --handoff-to-control
```

Default generated VM101 settings:

```text
name: ansible-control
vm_id: 101
ip_cidr: 192.168.1.211/24
gateway: 192.168.1.1
cpu: 2 cores, x86-64-v2
memory: 2048 MB
disk: 20 GB
```

Override these with:

```bash
--control-vm-name <name>
--control-vm-id <id>
--control-vm-ip-cidr <cidr>
--control-vm-gateway <ip>
--control-vm-cpu-type <type>
```

If the external runner cannot directly reach the VM subnet, the script reaches VM101 through the Proxmox host using SSH `ProxyJump`.

Inside VM101, the script writes an SSH alias:

```text
Host proxmox-rulab
  HostName <control-proxmox-ssh-host>
  User root
  IdentityFile /home/ubuntu/.ssh/ansible_ed25519
```

For the current lab, use the Proxmox bridge-side IP if VM101 should SSH to the host over `vmbr0`:

```bash
--control-proxmox-ssh-host 192.168.1.10
```

## Destructive clean-host rehearsal

Run this only from the external runner, never from VM101. In the current lab, the external runner is WSL Ubuntu with the public repo clone plus one local private site config:

```bash
cd /home/alexander/proxmox-remote-dev-platform
```

Create the local config once from the repo template:

```bash
mkdir -p ~/.config/proxmox-remote-dev-platform
cp config/site.example.yml ~/.config/proxmox-remote-dev-platform/site.yml
chmod 600 ~/.config/proxmox-remote-dev-platform/site.yml
nano ~/.config/proxmox-remote-dev-platform/site.yml
```

The local config is sensitive and must not be committed:

```text
/home/alexander/.config/proxmox-remote-dev-platform/site.yml
```

It contains the values that used to live in the private execution clone:

```text
Proxmox API token
Tailscale auth key
code-server password
lab IPs and VM/CT IDs
control VM settings
```

Before running a destructive wipe, verify the private inputs that must survive VM101/CT100 deletion:

```bash
test -f "$HOME/.ssh/ansible_ed25519" && echo "SSH key present"
grep -q 'api_token:' ~/.config/proxmox-remote-dev-platform/site.yml && echo "Proxmox token field present"
grep -q 'tskey-auth-' ~/.config/proxmox-remote-dev-platform/site.yml && echo "Tailscale auth key present"
```

Use a reusable/preauthorized Tailscale auth key if you want repeated destructive CT100 rebuilds without creating a new key each time.

The zero script materializes runtime execution files from `site.yml`, then copies that materialized execution tree to VM101 during handoff. These files live at the same paths as the sanitized placeholders, so do not commit after materialization.

### Current tested full wipe command

This is the current tested command for `proxmox-rulab` using the single config file:

```bash
bash scripts/rebuild_from_zero_lab.sh \
  --config ~/.config/proxmox-remote-dev-platform/site.yml \
  --apply \
  --wipe-existing-guests-and-templates \
  --manage-apt-repos \
  --create-template \
  --create-control-vm \
  --handoff-to-control \
  --with-provider-mirror
```

The same values can still be overridden on the CLI when needed, but normally `site.yml` supplies the Proxmox SSH hosts, API endpoints, SSH key path, and control VM settings.

This destroys all Proxmox VMs, all CTs, and local LXC templates on the target host before rebuilding:

```text
VM9000 ubuntu-22-template
VM101 ansible-control
VM110 dev-00
CT100 tailscale-rulab
```

It intentionally excludes the production GPU VM profile from the lab deployment.

Important: `--post-wipe-proxmox-host` must remain reachable after CT100 is destroyed. Do not point it at a Tailscale/remapped address served by CT100. If the only remote path to Proxmox is through the Tailscale LXC, a true full wipe cannot continue unattended; use a LAN/VPN/OOB management path first, or preserve CT100 until a replacement management path exists.

## Full non-GPU zero-to-lab run

On a fresh Proxmox host with root SSH ready and a local `site.yml` present, the generic form is:

```bash
bash scripts/bootstrap_control_runner.sh --with-opentofu-provider-mirror

bash scripts/rebuild_from_zero_lab.sh \
  --config ~/.config/proxmox-remote-dev-platform/site.yml \
  --apply \
  --wipe-existing-guests-and-templates \
  --manage-apt-repos \
  --create-template \
  --create-control-vm \
  --handoff-to-control \
  --with-provider-mirror
```

Legacy private-bundle mode remains available with `--private-bundle-root`, but the preferred workflow is now public repo + local site config.

For an already configured lab host where VM101/template already exist and you only want to retest VM110/CT100 recreation, use the lab-profile script from the generated VM101 execution directory instead of the full wipe:

```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private
TOFU_APPLY_TIMEOUT_SECONDS=180 \
LAB_PROXMOX_SSH_HOST=proxmox-rulab \
bash scripts/rebuild_lab_profile.sh --apply --destroy-existing
```

## OpenTofu timeout/import recovery behavior

During clean lab rebuilds, OpenTofu can create VM110/CT100 and then wait too long for first-boot QEMU guest-agent/network data. The lab-profile script now treats this as a recoverable partial apply:

```text
1. Wrap targeted `tofu apply` with TOFU_APPLY_TIMEOUT_SECONDS.
2. Verify VM110 and CT100 exist on Proxmox.
3. Enable the VM110 QGA device.
4. Wait for VM110 SSH/cloud-init.
5. Install/start qemu-guest-agent on VM110 if needed.
6. Import missing VM/CT resources into OpenTofu state.
7. Render inventory and continue Ansible convergence.
8. Require final targeted OpenTofu plan to return No changes.
```

Resource addresses used for import must quote map keys exactly:

```text
proxmox_virtual_environment_vm.dev["dev-00"]
proxmox_virtual_environment_container.tailscale_lxc["tailscale-rulab"]
```

## Validation criteria

Host-level:

```text
pveversion works
vmbr0 exists
local and local-lvm exist
/dev/net/tun exists
Debian 12 LXC template exists
Ubuntu template 9000 exists if create-template is enabled
OpenTofu API token exists / tofu/proxmox.env is materialized
```

Provisioning-level:

```text
OpenTofu creates VM 110 dev-00
OpenTofu creates CT 100 tailscale-rulab
OpenTofu excludes gpu-dev-01
OpenTofu post-Ansible targeted plan returns No changes
```

Configuration-level:

```text
Ansible can ping dev-00
Ansible can ping tailscale-rulab
qemu-guest-agent responds for dev-00
Docker/code-server/NFS base profile converges on dev-00
tailscaled is active in CT 100
/dev/net/tun is visible in CT 100
forwarding is enabled in CT 100
NETMAP/MASQUERADE rules are present and persisted
```

External Tailnet boundary:

```text
Tailscale route 192.168.2.0/24 still needs route approval unless ACL autoApprovers.routes is configured.
```

## What is still not zero-automated

Not yet automated:

```text
Proxmox ISO installation itself
BIOS/UEFI/storage controller setup
physical network cabling/VLAN switch config
Tailnet route approval unless ACL autoApprovers is configured
production GPU VM profile
shared storage data restore/backups
```

These are documented boundaries, not hidden assumptions.
