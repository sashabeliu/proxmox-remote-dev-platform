# Architecture

## Objective

Provide a rebuildable self-hosted remote development platform on Proxmox with a clean split between:
- provisioning
- configuration
- stateful data
- secrets
- documentation

## Layers

### 1. Hypervisor layer
- Proxmox VE host
- local storage and bridge networking
- VM and LXC lifecycle
- optional GPU passthrough mappings

### 2. Provisioning layer
- OpenTofu creates or recreates virtual machines from a base template
- network, CPU, RAM, disk, and guest initialization are described as code

### 3. Configuration layer
- Ansible configures the Proxmox host and the provisioned guests
- responsibilities include Docker, Tailscale, storage mounts, code-server, GPU guest setup, and developer workspace bootstrap

### 4. Access layer
- SSH access from operator workstation to Proxmox and control VM
- SSH from control VM to guest VMs
- Tailscale for remote connectivity where applicable

### 5. Shared storage layer
- NFS-backed shared storage served by `storage-vm`
- guest VMs mount shared content for datasets, models, outputs, and user workspace coordination

### 6. Workload layer
- development VMs
- GPU-enabled development VM(s)
- application repositories and runtime outputs

## Design principles

1. Infrastructure should be reproducible from code and docs.
2. Secrets should be injected, never committed.
3. Stateful data should be backed up outside git.
4. Recovery instructions should be explicit and testable.
5. The repo should be readable as a portfolio project, not only as an operator notebook.

## Recovery model

Rebuild speed comes from combining:
- infrastructure as code for machine creation
- configuration management for machine setup
- external backups for data and secrets
- runbooks for order-of-operations and validation
