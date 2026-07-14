# Rebuild Checklist

This checklist is the operator-facing sequence for rebuilding the platform from zero.

## Phase 0 - Confirm prerequisites

Before touching infrastructure, confirm all of the following are available:
- replacement host hardware or equivalent virtualization target
- Proxmox installation media
- this repository
- secret material required to replace placeholders in:
  - `tofu/proxmox.env`
  - `tofu/terraform.tfvars`
  - `ansible/group_vars/all.yml`
  - `ansible/group_vars/dev.yml`
  - `ansible/group_vars/gpu_dev.yml`
- access to GitHub repositories used by guest workloads
- backups for shared storage and other non-git state
- SSH access from operator workstation

## Phase 1 - Prepare Proxmox host

Checklist:
- install Proxmox VE
- configure management IP, gateway, and bridge networking
- verify SSH access as operator
- verify local storage and thinpool availability
- confirm any required PCI / GPU passthrough prerequisites on the host
- review `docs/proxmox-host-baseline.md`

Validation:
- Proxmox web UI reachable
- SSH reachable
- expected bridge exists
- expected storage names exist

## Phase 2 - Restore repo and secrets

Checklist:
- clone this repository
- review `docs/current-risks.md`
- review `docs/private-secret-bundle-workflow.md`
- review `docs/ansible-control-bootstrap.md`
- materialize private values with `scripts/materialize_private_config.sh --bundle-root <private-bundle-root>` or the Windows wrapper
- replace placeholder values in the required tracked sanitized files using private local values
- verify no placeholder values remain before applying any change

Suggested validation commands from repo root:
```bash
bash scripts/validate_repo_safety.sh --mode repo
bash scripts/validate_repo_safety.sh --mode deploy
```

Windows:
```text
scripts\\validate_repo_safety.cmd --mode repo
scripts\\validate_repo_safety.cmd --mode deploy
```

Expected result:
- `--mode repo` passes before commit/push
- `--mode deploy` passes only after execution-critical placeholders are replaced in a private working copy

## Phase 3 - Restore Proxmox baseline assets

Checklist:
- restore or recreate template VM used for cloning
- restore any required Proxmox host configuration not yet fully automated
- verify GPU passthrough mapping if GPU guests are required
- verify `target_node`, `template_vm_id`, and network assumptions in `tofu/terraform.tfvars`
- review `docs/template-vm-recovery.md`

Validation:
- template VM exists
- expected storage and bridge names match config
- GPU mapping is available if needed

## Phase 4 - Provision guests with OpenTofu

Checklist:
- review `tofu/main.tf`, `tofu/variables.tf`, `tofu/outputs.tf`
- verify `tofu/proxmox.env` and `tofu/terraform.tfvars`
- run OpenTofu init/plan/apply from `tofu/`

Example:
```bash
cd tofu
tofu init
tofu plan
tofu apply
```

Validation:
- expected VMs created
- expected VM IDs, CPU, RAM, disk, and IP assignments present
- no unexpected drift reported immediately after apply

## Phase 5 - Render inventory and configure guests

Checklist:
- generate inventory using `scripts/render_inventory.py`
- review `ansible/inventory/hosts.ini`
- run Ansible playbooks from `ansible/`
- review `docs/tailscale-recovery.md`
- review `docs/storage-vm-recovery.md`

Example flow:
```bash
python ../scripts/render_inventory.py
cd ../ansible
ansible-playbook -i inventory/proxmox-hosts.ini site-proxmox-hosts.yml
ansible-playbook -i inventory/hosts.ini site.yml
```

Validation:
- Ansible can ping all expected guests
- storage mounts succeed
- Docker is available on dev hosts
- Tailscale is configured as expected
- GPU guest has working GPU tooling if applicable

## Phase 6 - Restore stateful data

Checklist:
- restore `/srv/shared` or equivalent shared storage backup
- restore application repositories or pull from origin
- restore any machine-local non-git state that is still required
- verify per-app runtime prerequisites

Validation:
- NFS/shared storage mounted and populated
- app repos available and on expected branches
- required models/datasets/outputs restored where needed

## Phase 7 - Final acceptance

The rebuild is only considered successful when all are true:
- operator SSH access works
- Proxmox host is healthy
- control VM can provision or manage downstream guests
- dev VMs reachable
- shared storage works
- GPU workflows work on GPU guest(s)
- core app repos can be resumed without hidden manual tribal knowledge

## Follow-up after first successful rebuild

After a successful recovery, immediately:
- document any manual step that was still required
- reduce or eliminate that manual step in code or docs
- re-run the checklist as a dry run for future confidence
