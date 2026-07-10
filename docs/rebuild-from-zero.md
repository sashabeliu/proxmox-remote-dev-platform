# Rebuild From Zero

## Goal

Recover from a clean machine to a working remote development platform in the minimum practical time.

## Rebuild phases

### Phase 0 - External prerequisites
Prepare and verify:
- replacement hardware or host VM target
- Proxmox installation media
- access to secret store
- access to backup storage
- access to GitHub repositories
- SSH keys or emergency access credentials
- exported datasets and critical user data backups

### Phase 1 - Base Proxmox host
- install Proxmox VE
- configure management networking
- verify bridge and storage baseline
- verify operator SSH access

### Phase 2 - Recover repo and secrets
- clone this repository
- restore required secret files from secure backup location
- inject environment and variable files that are intentionally excluded from git

### Phase 3 - Configure Proxmox baseline
- apply host-level configuration steps
- restore or recreate template VM
- restore PCI mappings if GPU passthrough is required

### Phase 4 - Provision guests
- run OpenTofu from the provisioning layer
- verify expected VMs are created with correct IPs and resources
- render Ansible inventory

### Phase 5 - Configure guests
- run Ansible playbooks for guest configuration
- verify storage mounts, Docker, Tailscale, code-server, and GPU tooling as applicable

### Phase 6 - Restore stateful data
- restore NFS/shared data
- restore app repos or pull from origin
- restore any non-git machine-local runtime state that is still required

### Phase 7 - Validation
Verify:
- SSH access to all core guests
- NFS mounts
- GPU visibility on GPU guests
- Docker works on dev hosts
- Tailscale and remote access work
- app repositories are available and clean

## Target future improvement

This document should evolve into an exact command-level recovery runbook with:
- exact commands
- exact required files
- expected outputs
- rollback notes
