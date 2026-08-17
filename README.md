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
6. Create one local private site config from the template:
   - bash: `cp config/site.example.yml ~/.config/proxmox-remote-dev-platform/site.yml && chmod 600 ~/.config/proxmox-remote-dev-platform/site.yml`
   - then edit `~/.config/proxmox-remote-dev-platform/site.yml`
   - see `docs/site-config.md`
7. For the tested non-GPU lab recovery, run from the public repo clone with `--config`:
   - `bash scripts/rebuild_from_zero_lab.sh --config ~/.config/proxmox-remote-dev-platform/site.yml --apply --wipe-existing-guests-and-templates --manage-apt-repos --create-template --create-control-vm --handoff-to-control --with-provider-mirror`
8. The script materializes ignored runtime files from `site.yml` for execution and handoff. Do not commit those materialized real values.
9. Validate before commit/push with `--mode repo`; validate materialized execution contexts with `--mode deploy`.
10. Legacy private-bundle materialization still exists for compatibility, but it is no longer the preferred source-of-truth workflow.

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
- `docs/disaster-recovery-order-of-operations.md`
- `docs/rebuild-from-zero.md`
- `docs/rebuild-checklist.md`
- `docs/proxmox-host-baseline.md`
- `docs/template-vm-recovery.md`
- `docs/ansible-control-bootstrap.md`
- `docs/storage-vm-recovery.md`
- `docs/tailscale-recovery.md`
- `docs/backup-strategy.md`
- `docs/secrets-strategy.md`
- `docs/site-config.md`
- `docs/private-secret-bundle-workflow.md` (legacy compatibility)
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
    site-config.md
    private-secret-bundle-workflow.md
    current-risks.md
    state-vs-reproducible-assets.md
    portfolio-summary.md
  config/
    site.example.yml
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
- one local private `site.yml` is now the preferred private input; a separate maintained private repo is no longer required for the tested non-GPU lab recovery
- command-level zero-to-lab and lab-profile rebuild runbooks are documented and tested for the non-GPU lab scope
- the platform is documented, but not yet fully disaster-recovery hardened for production/GPU/stateful data

Known remaining work:
- move or protect live secrets with a stronger secret-management workflow
- define a safer OpenTofu state strategy
- configure and test real backup jobs
- capture application-level drift and restore rules for guest workloads
- keep GPU/production-shaped rebuilds deferred until matching hardware capacity and PCI mappings are available
