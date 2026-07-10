# Secrets Strategy

## Rule

This repository stores interfaces and examples, not live secrets.

## Secrets currently expected in the platform
- Proxmox API credentials
- OpenTofu variable values
- Tailscale auth key or auth flow material
- SSH private keys
- GitHub tokens or deploy credentials
- code-server authentication values
- any application-specific secrets used on guests

## Repository pattern

This repository uses an in-place sanitized layout where that improves rebuild clarity. Some files are intentionally tracked at their real relative paths, but only with placeholder values.

Commit:
- sanitized in-place placeholder files where path clarity matters
- `*.example` files
- documentation of where secrets are consumed
- references to required variable names

Do not commit:
- live `.env` values
- live `terraform.tfvars` values
- real inventory host secrets
- raw private key material

## Suggested implementation pattern

### OpenTofu
Commit:
- `variables.tf`
- `main.tf`
- `outputs.tf`
- `versions.tf`
- sanitized `terraform.tfvars`
- sanitized `proxmox.env`
- `*.example` files

Do not commit:
- live values inside `terraform.tfvars`
- live values inside `proxmox.env`
- `.tfstate`

### Ansible
Commit:
- playbooks
- roles
- defaults
- sanitized inventory
- sanitized group vars

Do not commit:
- live secret values in tracked var files
- vault passwords
- private keys

## Future options
- Ansible Vault
- SOPS + age
- 1Password / Bitwarden / Vault-backed operator workflow

## Minimum acceptable operator workflow
1. clone repo
2. restore secret bundle from secure source
3. place secrets into documented local paths
4. run validation before any apply step
