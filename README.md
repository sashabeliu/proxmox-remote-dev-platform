# proxmox-remote-dev-platform

Reproducible Proxmox-based remote development platform with OpenTofu, Ansible, Tailscale, shared storage, and recovery documentation.

## Goal

This repository is the recovery, rebuild, and portfolio source of truth for a self-hosted remote development platform.

The target outcome is:
- rebuild a clean Proxmox host into a working remote development platform quickly
- preserve infrastructure knowledge outside of any single machine
- separate reproducible infrastructure from stateful data and secrets
- document the architecture in a way that is understandable as a portfolio project

## Quick start

1. Read `docs/rebuild-checklist.md` for the operator sequence.
2. Read `docs/state-vs-reproducible-assets.md` to understand what is rebuilt versus restored.
3. Review `docs/current-risks.md` before trusting the platform as disaster-recovery ready.
4. Install the repo-managed git hooks:
   - bash: `bash scripts/install_git_hooks.sh`
   - Windows: `scripts\install_git_hooks.cmd`
5. Run repo-safety validation before commit/push:
   - bash: `bash scripts/validate_repo_safety.sh --mode repo`
   - Windows: `scripts\validate_repo_safety.cmd --mode repo`
   - GitHub Actions also runs this check on push and pull request via `.github/workflows/repo-safety.yml`
6. Materialize private execution values into a private working copy:
   - bash: `bash scripts/materialize_private_config.sh --bundle-root <private-bundle-root>`
   - Windows: `scripts\materialize_private_config.cmd --bundle-root <private-bundle-root>`
   - the bundle root may be either the repo-specific secret directory or its parent directory
7. If you are copying values manually instead of using the helper, replace placeholders only in your private working copy or in secret-managed deployment locations:
   - `tofu/proxmox.env`
   - `tofu/terraform.tfvars`
   - `ansible/group_vars/all.yml`
   - `ansible/group_vars/dev.yml`
   - `ansible/group_vars/gpu_dev.yml`
8. Validate the private working copy before running apply/playbook steps:
   - bash: `bash scripts/validate_repo_safety.sh --mode deploy`
   - Windows: `scripts\validate_repo_safety.cmd --mode deploy`
9. Apply provisioning from `tofu/`, then configuration from `ansible/`, then restore stateful data.

## Recovery flow

The intended long-term rebuild order is:
1. prepare clean host prerequisites
2. install and baseline Proxmox host
3. restore this repo and secret material
4. restore template VM and Proxmox-specific baseline
5. provision guests with OpenTofu
6. render inventory and configure guests with Ansible
7. restore shared data and application state
8. validate SSH, storage, GPU, Docker, Tailscale, and developer workflows

See:
- `docs/rebuild-from-zero.md`
- `docs/rebuild-checklist.md`
- `docs/backup-strategy.md`

## Documentation guide

Architecture and platform overview:
- `docs/architecture.md`
- `docs/topology.md`
- `docs/portfolio-summary.md`

Recovery and operations:
- `docs/rebuild-from-zero.md`
- `docs/rebuild-checklist.md`
- `docs/proxmox-host-baseline.md`
- `docs/template-vm-recovery.md`
- `docs/ansible-control-bootstrap.md`
- `docs/storage-vm-recovery.md`
- `docs/tailscale-recovery.md`
- `docs/backup-strategy.md`
- `docs/secrets-strategy.md`
- `docs/private-secret-bundle-workflow.md`
- `docs/current-risks.md`
- `docs/state-vs-reproducible-assets.md`

Observed live-state snapshot:
- `docs/proxmox-current-state.md`

## Current scope

This repo is intended to hold:
- infrastructure provisioning design and sanitized OpenTofu configuration
- guest and host configuration management design and sanitized Ansible structure
- rebuild and disaster-recovery documentation
- backup policy and restore procedure documentation
- sanitized examples and templates for inventory, vars, and environment files

This repo must not hold:
- live private keys
- API tokens
- Tailscale auth keys
- real `terraform.tfvars`
- `.tfstate` files
- cloud-init passwords
- datasets, model artifacts, videos, or other large runtime outputs

Sanitized placeholder files are intentionally kept in their live relative paths where that improves rebuild clarity, including `tofu/terraform.tfvars`, `tofu/proxmox.env`, and `ansible/group_vars/*.yml`. Those tracked files must stay sanitized.

## Repository layout

```text
proxmox-remote-dev-platform/
  README.md
  docs/
    architecture.md
    topology.md
    proxmox-current-state.md
    rebuild-from-zero.md
    rebuild-checklist.md
    backup-strategy.md
    secrets-strategy.md
    private-secret-bundle-workflow.md
    current-risks.md
    state-vs-reproducible-assets.md
    portfolio-summary.md
  tofu/
  ansible/
  scripts/
  examples/
  .gitignore
```

## Source systems discovered during read-only audit

Provisioning layer:
- `~/infra/tofu` on `ansible-control`
- Proxmox provider: `bpg/proxmox`
- OpenTofu state currently stored locally on the VM

Configuration layer:
- `~/infra-ansible` on `ansible-control`
- Playbooks and roles configure Proxmox host, dev VMs, GPU VM, storage client/server, Docker, Tailscale, code-server, and Git workspace setup

Runtime/data layer:
- shared storage exported from `storage-vm` via NFS from `/srv/shared`
- app repo example discovered on dev VMs: `iris-poc`
- runtime outputs and datasets are outside the scope of git and require backup policy

## Current status

Current repo state:
- local baseline was created and pushed to GitHub
- sanitized OpenTofu and Ansible content has been imported into the repo
- same-path sanitized placeholders are being used for clarity
- the platform is documented, but not yet fully disaster-recovery hardened

Known remaining work:
- finish exact command-level rebuild runbooks
- move or protect live secrets with a stronger secret-management workflow
- define a safer OpenTofu state strategy
- configure and test real backup jobs
- capture application-level drift and restore rules for guest workloads
