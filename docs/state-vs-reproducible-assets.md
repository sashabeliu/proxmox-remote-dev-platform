# State vs Reproducible Assets

This document separates what should be recreated from code from what must be restored from backup.

## Category A - Reproducible from code and docs

These are intended to be rebuilt, not manually copied from a surviving system.

### Proxmox provisioning layer
Location in repo:
- `tofu/`
- `scripts/render_inventory.py`
- `scripts/provision_all.sh`
- `scripts/provision_and_configure.sh`

Examples:
- VM definitions
- CPU/RAM/disk/network configuration intent
- OpenTofu outputs used to feed configuration

Recovery method:
- restore repo
- inject secrets
- run OpenTofu

### Configuration management layer
Location in repo:
- `ansible/site.yml`
- `ansible/site-proxmox-hosts.yml`
- `ansible/roles/`
- `ansible/inventory/`
- `ansible/group_vars/` (sanitized tracked placeholders)

Examples:
- package installation
- Docker configuration
- Tailscale setup
- NFS client/server config
- code-server setup
- workspace bootstrap

Recovery method:
- restore repo
- inject secrets
- run Ansible

### Documentation and runbooks
Location in repo:
- `docs/`
- `README.md`

Recovery method:
- clone repo
- follow docs

## Category B - Tracked but sanitized interfaces

These files stay in their real relative paths for clarity, but only sanitized placeholders should be committed.

Examples:
- `tofu/proxmox.env`
- `tofu/terraform.tfvars`
- `ansible/group_vars/all.yml`
- `ansible/group_vars/dev.yml`
- `ansible/group_vars/gpu_dev.yml`

Recovery method:
- replace placeholders from secret source before apply

## Category C - Secret material

These are required for successful recovery but must live outside git.

Examples:
- Proxmox API token values
- Tailscale auth keys
- private SSH keys
- GitHub tokens
- any passwords or secret app credentials

Recovery method:
- restore from secret manager or secure offline backup
- inject into tracked placeholder paths or into runtime-only private files

## Category D - Stateful data that must be backed up

These are not recreated by OpenTofu or Ansible.

Examples observed during audit:
- `/srv/shared`
- datasets
- models
- publish outputs
- user-generated working data
- any app-local files not committed upstream

Recovery method:
- restore from backup system after infra and configuration are working

## Category E - Hybrid / ambiguous assets

These require a deliberate decision because they are partly reproducible and partly stateful.

Examples:
- guest application repositories with local drift
- template VM image lifecycle
- OpenTofu state file
- generated inventories that include static manual hosts

Required decision for each hybrid asset:
- can it be rebuilt?
- must it be backed up?
- is it a temporary bridge that should be simplified later?

## Operator rule of thumb

Ask two questions for any asset:
1. Can I recreate this reliably from git plus documented secrets?
2. If not, where is its backup and what is the restore step?

If neither answer is clear, the platform is not yet rebuild-ready.
