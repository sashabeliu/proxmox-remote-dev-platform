# proxmox-remote-dev-platform

Reproducible Proxmox-based remote development platform with OpenTofu, Ansible, Tailscale, shared storage, and recovery documentation.

## Goal

This repository is the recovery, rebuild, and portfolio source of truth for a self-hosted remote development platform.

The target outcome is:
- rebuild a clean Proxmox host into a working remote development platform quickly
- preserve infrastructure knowledge outside of any single machine
- separate reproducible infrastructure from stateful data and secrets
- document the architecture in a way that is understandable as a portfolio project

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
    backup-strategy.md
    secrets-strategy.md
    portfolio-summary.md
  tofu/
    README.md
  ansible/
    README.md
  scripts/
    README.md
  examples/
    README.md
    tofu/
      terraform.tfvars.example
      proxmox.env.example
    ansible/
      hosts.ini.example
      group_vars/
        all.yml.example
        dev.yml.example
        gpu_dev.yml.example
        storage.yml.example
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

## Build strategy

The intended long-term build order is:
1. prepare clean host prerequisites
2. configure Proxmox host baseline
3. provision VMs with OpenTofu
4. render inventory for Ansible
5. configure guests with Ansible
6. restore stateful data from backup
7. validate access, storage, GPU, and developer workflows

## Next implementation steps

1. import and sanitize the existing `~/infra/tofu` content into `tofu/`
2. import and sanitize the existing `~/infra-ansible` content into `ansible/`
3. replace live secrets with examples plus documented secret injection flow
4. add exact rebuild commands and validation steps
5. define external backup locations for secrets, state, and shared data
6. optionally publish the repo to GitHub once sanitized

## Status

Initial scaffold created locally. This is a documentation-first baseline, not yet a full export of the live infrastructure.
