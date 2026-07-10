# Backup Strategy

## Principle

Not everything should be backed up in the same way.

Use three categories:
1. git-tracked reproducible infrastructure
2. secret material stored in secure secret backup
3. stateful data stored in backup systems outside git

## 1. Git-tracked reproducible assets
These belong in the repo after sanitization:
- OpenTofu configuration
- Ansible playbooks and roles
- inventory examples
- rebuild docs
- architecture docs
- validation scripts
- runbooks

## 2. Secret material
These must never be committed:
- Proxmox API token env files
- live `terraform.tfvars`
- Tailscale auth keys
- private SSH keys
- code-server passwords
- cloud-init passwords
- GitHub tokens

Recommended handling:
- secret manager or encrypted vault
- offline backup copy
- documented restore procedure

## 3. Stateful data
Back up outside git:
- `/srv/shared` data
- datasets
- model artifacts
- published outputs
- user work products not stored in upstream repos
- any machine-local files required for fast resume

## 4. VM-level backups
Desired future state:
- scheduled Proxmox backup jobs for critical VMs
- regular snapshots only where operationally useful
- tested restore path, not only backup creation

## Backup priorities

### Highest priority
- secrets
- shared storage data
- recovery repo itself
- OpenTofu state or a safer remote-state replacement

### Medium priority
- guest machine images for faster recovery
- template VM export

### Lower priority
- fully reproducible caches and disposable build artifacts

## Gap noted during audit
No scheduled Proxmox backup jobs were observed. That should be fixed early in the project.
