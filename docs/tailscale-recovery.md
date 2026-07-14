# Tailscale Recovery

## Purpose
Recover the Tailscale configuration that the repo currently manages for guest VMs.

## Current managed scope
Tracked config currently applies the `tailscale` role to:
- `dev`
- `gpu_dev`

Current shared vars:
- `ansible/group_vars/all.yml`
  - `tailscale_auth_key`
  - `tailscale_args`
  - `tailscale_exit_node`
  - `tailscale_exit_node_allow_lan_access`
  - `tailscale_debug`

Observed current values in the sanitized repo:
- `tailscale_args: "--ssh"`
- `tailscale_exit_node: "tailscale-redundent.tail20bec0.ts.net"`
- `tailscale_exit_node_allow_lan_access: true`

## Important current limitation
This repo does not currently codify Tailscale recovery for all observed nodes.
Observed but not fully managed here:
- LXC `100` `mltailscale`
- `ansible-control`
- `storage-vm`

This document therefore covers only the Tailscale behavior that is actually present in the tracked Ansible role.

## What the repo-managed role does
The `ansible/roles/tailscale` role:
1. installs Tailscale from the upstream install script
2. enables and starts `tailscaled`
3. runs `tailscale up --reset`
4. sets:
   - `--authkey={{ tailscale_auth_key }}`
   - `--hostname={{ inventory_hostname }}`
   - `{{ tailscale_args }}`
   - optional advertised tags
5. optionally applies an exit node using `tailscale set`
6. reads final status with `tailscale status --json`

## Recovery steps for repo-managed guests
1. Restore a valid Tailscale auth key in the private secret bundle.
2. Materialize private values into the private working copy.
3. Run guest configuration with Ansible.
4. Verify the dev and GPU guests join the Tailnet with the expected hostnames.

## Recovery command
From the configured control environment:
```bash
cd ansible
ansible-playbook -i inventory/hosts.ini site.yml
```

## Validation
The Tailscale recovery is acceptable only when all are true:
- `tailscaled` is active on the intended guests
- guests appear in the Tailnet with the expected hostnames
- SSH-over-Tailscale works if `--ssh` is still intended
- exit node settings apply as expected on those guests

## Manual checks
Useful checks after recovery:
- `tailscale status`
- `tailscale ip`
- `systemctl status tailscaled`
- verify Tailnet presence in the admin console

## Known gaps
- no codified recovery yet for `mltailscale`
- no codified recovery yet for Tailscale on `ansible-control`
- no codified recovery yet for Tailscale on `storage-vm`
- auth key lifecycle / rotation policy is not yet documented here
