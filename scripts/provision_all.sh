#!/usr/bin/env bash
set -euo pipefail

ANSIBLE_DIR="$HOME/infra-ansible"
TOFU_DIR="$HOME/infra/tofu"
SCRIPT_DIR="$HOME/infra/scripts"

echo "===> Bootstrap Proxmox host"
ansible-playbook -i "$ANSIBLE_DIR/inventory/proxmox-hosts.ini" "$ANSIBLE_DIR/site-proxmox-hosts.yml"

echo "===> Provision VMs with OpenTofu"
cd "$TOFU_DIR"
tofu apply -auto-approve

echo "===> Render Ansible inventory"
"$SCRIPT_DIR/render_inventory.py"

echo "===> Configure guest VMs"
ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site.yml"

echo "===> Done"
