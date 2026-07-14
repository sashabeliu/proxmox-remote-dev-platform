# Disaster Recovery Order of Operations

## Goal
Recover the platform in the correct order with the fewest hidden assumptions.

Use this page as the short operator runbook.
Use the linked component docs only when a step needs more detail.

## 0. Confirm you have the required inputs
You need all of these before starting:
- replacement Proxmox host or equivalent target
- Proxmox installer/media
- this repo
- private secret bundle
- backup of `/srv/shared`
- SSH access from your workstation
- access to GitHub repos used by workloads
- if needed: template VM backup/export

Stop if any of these are missing.

## 1. Reinstall the Proxmox host
Do this on the replacement host:
- install Proxmox VE
- recreate management IP
- recreate gateway
- recreate `vmbr0`
- verify `local` and `local-lvm`
- verify root SSH access

Decision point:
- if GPU guests are required, continue with GPU host baseline
- otherwise skip GPU-specific validation

Reference:
- `docs/proxmox-host-baseline.md`

## 2. Recreate the template VM
You need a usable clone source before OpenTofu can create guests.

Do this in Proxmox:
- restore template VM backup/export if available
- otherwise recreate the Ubuntu template manually
- ensure the template ID matches `template_vm_id` in `tofu/terraform.tfvars`
- ensure guest agent and cloud-init style initialization are usable

Current tracked expectation:
- template ID: `9000`

Stop if the template cannot be cloned successfully.

Reference:
- `docs/template-vm-recovery.md`

## 3. Recreate the control VM
You need `ansible-control` before the repo can drive the rest of recovery.

Do this:
- restore or recreate VM `101` `ansible-control`
- ensure SSH works as `ubuntu`
- install required tools:
  - `git`
  - `python3`
  - `ssh`
  - `ansible-playbook`
  - `tofu`
- restore `/home/ubuntu/.ssh/ansible_ed25519`

Important note:
- exact package install commands for this VM are not yet pinned in the repo

Reference:
- `docs/ansible-control-bootstrap.md`

## 4. Clone the repo on the control VM
Recommended pattern:
- one public/safe clone
- one private execution clone

Example:
```bash
cd /home/ubuntu
git clone https://github.com/sashabeliu/proxmox-remote-dev-platform.git proxmox-remote-dev-platform
git clone https://github.com/sashabeliu/proxmox-remote-dev-platform.git proxmox-remote-dev-platform-private
```

Use the private clone for all secret materialization and apply/playbook runs.

## 5. Materialize secrets into the private clone
From the private clone:
```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private
bash scripts/materialize_private_config.sh --bundle-root <private-bundle-root>
bash scripts/validate_repo_safety.sh --mode deploy
```

Expected result:
- materialization succeeds
- deploy validation passes

Stop if deploy validation fails.

Reference:
- `docs/private-secret-bundle-workflow.md`

## 6. Optional: recreate legacy helper paths
Do this only if you want the old helper scripts to work unchanged.

```bash
mkdir -p /home/ubuntu/infra
ln -sfn /home/ubuntu/proxmox-remote-dev-platform-private/tofu /home/ubuntu/infra/tofu
ln -sfn /home/ubuntu/proxmox-remote-dev-platform-private/scripts /home/ubuntu/infra/scripts
ln -sfn /home/ubuntu/proxmox-remote-dev-platform-private/ansible /home/ubuntu/infra-ansible
```

If you do not need legacy helpers, skip this and run commands manually from the monorepo.

## 7. Apply Proxmox host baseline automation
From the private clone:
```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private/ansible
ansible-playbook -i inventory/proxmox-hosts.ini site-proxmox-hosts.yml
```

This is mainly required for GPU passthrough preparation on the Proxmox host.

Decision point:
- if GPU passthrough is part of recovery, validate VFIO before continuing
- if not, continue

Reference:
- `docs/proxmox-host-baseline.md`

## 8. Provision guests with OpenTofu
From the private clone:
```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private/tofu
tofu init
tofu plan
tofu apply
```

Expected result:
- expected guest VMs are created
- IDs, RAM, CPU, disk, and IPs match tracked config

Stop if OpenTofu cannot reach Proxmox or cloning fails.

## 9. Render guest inventory
From the private clone:
```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private/tofu
python ../scripts/render_inventory.py
```

Expected result:
- `ansible/inventory/hosts.ini` is refreshed
- dev/gpu guests appear
- static `storage-vm` entry remains present

## 10. Configure guests with Ansible
From the private clone:
```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private/ansible
ansible-playbook -i inventory/hosts.ini site.yml
```

This configures, depending on host group:
- Tailscale
- common packages
- Docker
- NFS storage client/server
- Git SSH / deploy key workflow
- workspace bootstrap
- code-server
- project bring-up
- NVIDIA tooling on GPU guests

## 11. Restore shared storage state
Recover `storage-vm` and `/srv/shared`.

Do this:
- restore or recreate `storage-vm`
- restore `/srv/shared` from backup
- confirm `storage-vm` is reachable at the intended IP or update vars deliberately
- rerun guest config if mounts need to be re-applied

Reference:
- `docs/storage-vm-recovery.md`

## 12. Validate Tailscale
For repo-managed guests, verify:
- `tailscaled` is running
- hosts joined the Tailnet
- SSH-over-Tailscale works if still intended
- exit node settings applied if still intended

Reference:
- `docs/tailscale-recovery.md`

## 13. Final acceptance checks
Recovery is acceptable only if all are true:
- Proxmox UI works
- root SSH to Proxmox works
- template exists and clones cleanly
- `ansible-control` works
- OpenTofu runs successfully
- Ansible runs successfully
- dev VMs reachable
- GPU guest reachable and GPU tooling works if required
- `/mnt/shared` is mounted on guests
- `/srv/shared` data is restored
- Tailscale works where expected
- app repos can resume without hidden manual tribal knowledge

## Fast reference commands
Private clone setup:
```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private
bash scripts/materialize_private_config.sh --bundle-root <private-bundle-root>
bash scripts/validate_repo_safety.sh --mode deploy
```

Host baseline:
```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private/ansible
ansible-playbook -i inventory/proxmox-hosts.ini site-proxmox-hosts.yml
```

Provision:
```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private/tofu
tofu init
tofu plan
tofu apply
```

Render inventory:
```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private/tofu
python ../scripts/render_inventory.py
```

Guest config:
```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private/ansible
ansible-playbook -i inventory/hosts.ini site.yml
```

## Known remaining gaps
This page is useful, but the platform is not yet fully rebuild-hard:
- exact template build steps are still not pinned command-by-command
- exact package install commands for `ansible-control` are still not pinned
- `storage-vm` is still manual/static, not OpenTofu-managed
- Tailscale recovery is only codified for repo-managed guests, not every observed node
- scheduled Proxmox backup jobs were not observed during audit
- OpenTofu state handling still needs hardening
