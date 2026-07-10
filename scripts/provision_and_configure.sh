#!/usr/bin/env bash
set -euo pipefail

TOFU_DIR="${HOME}/infra/tofu"
ANSIBLE_DIR="${HOME}/infra-ansible"
SCRIPT_DIR="${HOME}/infra/scripts"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/hosts.ini"

echo "==> Running OpenTofu apply"
cd "${TOFU_DIR}"
tofu apply -auto-approve

echo "==> Rendering Ansible inventory and refreshing SSH known_hosts"
"${SCRIPT_DIR}/render_inventory.py"

echo "==> Reading OpenTofu outputs"
HOSTS_JSON="$(tofu output -json ansible_hosts)"
export HOSTS_JSON

echo "==> Waiting for SSH on provisioned hosts"
python3 - <<'PY'
import json
import os
import socket
import time

hosts = json.loads(os.environ["HOSTS_JSON"])

def wait_ssh(ip, timeout=600):
    start = time.time()
    while time.time() - start < timeout:
        s = socket.socket()
        s.settimeout(3)
        try:
            s.connect((ip, 22))
            s.close()
            return True
        except Exception:
            time.sleep(5)
    return False

for name, data in hosts.items():
    ip = data["ip"]
    print(f"Waiting for SSH on {name} ({ip})...")
    if not wait_ssh(ip):
        raise SystemExit(f"Timeout waiting for SSH on {name} ({ip})")
PY

echo "==> Waiting for cloud-init to complete on provisioned hosts"
ansible all -i "${INVENTORY_FILE}" -m shell -a "cloud-init status --wait || true"

echo "==> Waiting for apt/dpkg lock to be released on provisioned hosts"
ansible all -i "${INVENTORY_FILE}" -m shell -a "while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 2; done"

echo "==> Verifying storage reachability"
ansible storage -i "${INVENTORY_FILE}" -m ping

echo "==> Running Ansible guest configuration"
cd "${ANSIBLE_DIR}"
ansible-playbook -i "${INVENTORY_FILE}" site.yml

echo "==> Done"
