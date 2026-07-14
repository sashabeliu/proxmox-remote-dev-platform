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

Exact package source / installation commands for these tools are not yet pinned in the repo.

## Recommended operator pattern
- keep one safe/public clone for git work
- keep one private execution clone for materialized secrets and apply/playbook runs

Example repo locations:
- public clone: `/home/ubuntu/proxmox-remote-dev-platform`
- private clone: `/home/ubuntu/proxmox-remote-dev-platform-private`

## Bootstrap steps
1. Recreate the control VM and ensure SSH access as `ubuntu`.
2. Install the required tooling listed above.
3. Clone this repo to a public path.
4. Create a private execution clone.
5. Restore `/home/ubuntu/.ssh/ansible_ed25519` with correct permissions.
6. Materialize private values into the private clone.
7. Run deploy validation in the private clone.
8. Either run commands manually from the private clone or create compatibility symlinks for the legacy helpers.

## Compatibility symlink option
If you want the current helper scripts to work without editing them, point the old paths at the private clone.

Example:
```bash
mkdir -p /home/ubuntu/infra
ln -sfn /home/ubuntu/proxmox-remote-dev-platform-private/tofu /home/ubuntu/infra/tofu
ln -sfn /home/ubuntu/proxmox-remote-dev-platform-private/scripts /home/ubuntu/infra/scripts
ln -sfn /home/ubuntu/proxmox-remote-dev-platform-private/ansible /home/ubuntu/infra-ansible
```

## Secret materialization
From the private clone:
```bash
bash scripts/materialize_private_config.sh --bundle-root <private-bundle-root>
bash scripts/validate_repo_safety.sh --mode deploy
```

## Manual recovery flow from the monorepo
From the private clone:
```bash
cd tofu
tofu init
tofu plan
tofu apply
python ../scripts/render_inventory.py
cd ../ansible
ansible-playbook -i inventory/proxmox-hosts.ini site-proxmox-hosts.yml
ansible-playbook -i inventory/hosts.ini site.yml
```

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
- exact package install commands for `tofu` and `ansible` are not yet captured here
- control VM creation is still manual/static, not OpenTofu-managed
- OpenTofu state remains a control-plane recovery dependency and must be backed up separately
