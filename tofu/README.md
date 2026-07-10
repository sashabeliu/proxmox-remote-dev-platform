# OpenTofu Layer

This directory will hold the sanitized provisioning layer for the Proxmox platform.

## Intended contents
- provider and version declarations
- variable schema
- VM definitions
- outputs used by the Ansible layer
- helper modules if the configuration grows

## Import target from live system
Observed live source:
- `~/infra/tofu` on `ansible-control`

## Expected migration tasks
- copy `main.tf`, `variables.tf`, `outputs.tf`, and `versions.tf`
- sanitize or replace live values from `terraform.tfvars`
- remove local `.tfstate` from version control
- document how state should be handled safely
