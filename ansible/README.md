# Ansible Layer

This directory will hold the sanitized configuration-management layer for the platform.

## Intended contents
- inventory templates
- playbooks
- roles
- defaults and example vars
- validation or bootstrap helpers

## Import target from live system
Observed live source:
- `~/infra-ansible` on `ansible-control`

## Expected migration tasks
- copy playbooks and roles
- replace live secrets with examples or encrypted secret handling
- split generated inventory from source-controlled inventory templates
- document how provisioning output feeds configuration input
