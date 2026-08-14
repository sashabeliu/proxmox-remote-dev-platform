#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/rebuild_lab_profile.sh [--apply] [--destroy-existing] [--skip-host-preflight] [--skip-ansible] [--full-dev]

Lab rebuild profile for proxmox-rulab. GPU VM gpu-dev-01 is intentionally excluded.

Default is plan/check mode: no OpenTofu apply and no destructive cleanup.

Options:
  --apply              Run OpenTofu apply and Ansible configuration. Without this, only plan/syntax/preflight steps run.
  --destroy-existing   Before apply, remove lab-profile guests from Proxmox: VM 110 dev-00 and CT 100 tailscale-rulab.
                       Requires --apply.
  --skip-host-preflight
                       Skip Proxmox-host LXC preflight/post-create role.
  --skip-ansible       Skip guest/LXC Ansible configuration after OpenTofu apply.
  --full-dev           Use ansible/site.yml --limit dev,tailscale_lxc after apply. Requires fresh guest Tailscale/GitHub/repo creds.
                       By default, uses ansible/site-lab-profile.yml, which excludes gpu_dev and skips dev guest Tailscale/GitHub workspace roles.

Environment overrides:
  LAB_PROXMOX_SSH_HOST  SSH alias/host for lab Proxmox root access. Default: proxmox-rulab
  PROXMOX_HOST_INVENTORY Ansible inventory for Proxmox-host plays. Default: ansible/inventory/proxmox-hosts.ini
  DEV_VM_TARGET         OpenTofu dev VM key. Default: dev-00
  DEV_VM_ID             Proxmox VMID for DEV_VM_TARGET. Default: 110
  DEV_VM_IP_CIDR        Lab-safe dev VM IP. Default: 192.168.1.112/24
  DEV_VM_CPU_CORES      Lab-safe dev VM vCPU count. Default: 4
  LXC_TARGET            OpenTofu Tailscale LXC key. Default: tailscale-rulab
  LXC_ID                Proxmox CTID for LXC_TARGET. Default: 100
  LXC_IP_CIDR           Lab-safe Tailscale LXC IP. Default: 192.168.1.212/24
  LAB_GATEWAY           Lab LAN gateway. Default: 192.168.1.1
  TOFU_APPLY_TIMEOUT_SECONDS
                         Max seconds to wait for targeted OpenTofu apply before continuing if guests exist. Default: 900
EOF
}

APPLY=0
DESTROY_EXISTING=0
SKIP_HOST_PREFLIGHT=0
SKIP_ANSIBLE=0
FULL_DEV=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --destroy-existing) DESTROY_EXISTING=1; shift ;;
    --skip-host-preflight) SKIP_HOST_PREFLIGHT=1; shift ;;
    --skip-ansible) SKIP_ANSIBLE=1; shift ;;
    --full-dev) FULL_DEV=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$DESTROY_EXISTING" -eq 1 && "$APPLY" -ne 1 ]]; then
  echo "error: --destroy-existing requires --apply" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOFU_DIR="$REPO_ROOT/tofu"
ANSIBLE_DIR="$REPO_ROOT/ansible"
LAB_PROXMOX_SSH_HOST="${LAB_PROXMOX_SSH_HOST:-proxmox-rulab}"
PROXMOX_HOST_INVENTORY="${PROXMOX_HOST_INVENTORY:-$ANSIBLE_DIR/inventory/proxmox-hosts.ini}"
DEV_VM_TARGET="${DEV_VM_TARGET:-dev-00}"
DEV_VM_ID="${DEV_VM_ID:-110}"
DEV_VM_IP_CIDR="${DEV_VM_IP_CIDR:-192.168.1.112/24}"
DEV_VM_IP="${DEV_VM_IP_CIDR%%/*}"
DEV_VM_CPU_CORES="${DEV_VM_CPU_CORES:-4}"
DEV_VM_MEMORY_MB="${DEV_VM_MEMORY_MB:-8192}"
DEV_VM_DISK_GB="${DEV_VM_DISK_GB:-80}"
LXC_TARGET="${LXC_TARGET:-tailscale-rulab}"
LXC_ID="${LXC_ID:-100}"
LXC_IP_CIDR="${LXC_IP_CIDR:-192.168.1.212/24}"
LXC_CPU_CORES="${LXC_CPU_CORES:-1}"
LXC_MEMORY_MB="${LXC_MEMORY_MB:-1024}"
LXC_SWAP_MB="${LXC_SWAP_MB:-1024}"
LXC_DISK_GB="${LXC_DISK_GB:-8}"
LXC_TEMPLATE_FILE_ID="${LXC_TEMPLATE_FILE_ID:-local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst}"
LXC_TEMPLATE_FILE="${LXC_TEMPLATE_FILE:-debian-12-standard_12.12-1_amd64.tar.zst}"
LAB_GATEWAY="${LAB_GATEWAY:-192.168.1.1}"
PLAN_FILE="${TMPDIR:-/tmp}/lab-profile-${DEV_VM_TARGET}-${LXC_TARGET}.tfplan"
LAB_TFVARS="$TOFU_DIR/lab-profile.auto.tfvars.json"
TOFU_APPLY_TIMEOUT_SECONDS="${TOFU_APPLY_TIMEOUT_SECONDS:-900}"
ANSIBLE_SSH_KEY_FILE="${ANSIBLE_SSH_KEY_FILE:-/home/ubuntu/.ssh/ansible_ed25519}"

TOFU_TARGETS=(
  "proxmox_virtual_environment_vm.dev[\"${DEV_VM_TARGET}\"]"
  "proxmox_virtual_environment_container.tailscale_lxc[\"${LXC_TARGET}\"]"
)

say() { printf '\n== %s ==\n' "$*"; }
run() { printf '+ %q ' "$@"; printf '\n'; "$@"; }
redact() { sed -E 's/tskey-[A-Za-z0-9-]+/[REDACTED_TSKEY]/g; s/(token|secret|password|authkey|auth_key)[^[:space:]]*/[REDACTED]/Ig'; }

write_lab_profile_overrides() {
  say "Write generated lab profile overrides"
  python3 - "$LAB_TFVARS" "$DEV_VM_TARGET" "$DEV_VM_ID" "$DEV_VM_IP_CIDR" "$LAB_GATEWAY" "$DEV_VM_CPU_CORES" "$DEV_VM_MEMORY_MB" "$DEV_VM_DISK_GB" "$LXC_TARGET" "$LXC_ID" "$LXC_IP_CIDR" "$LXC_CPU_CORES" "$LXC_MEMORY_MB" "$LXC_SWAP_MB" "$LXC_DISK_GB" "$LXC_TEMPLATE_FILE_ID" <<'PY'
import json, sys
(
    path,
    dev_name, dev_id, dev_ip, gateway, dev_cpu, dev_mem, dev_disk,
    lxc_name, lxc_id, lxc_ip, lxc_cpu, lxc_mem, lxc_swap, lxc_disk, lxc_template,
) = sys.argv[1:]
data = {
    "dev_vms": {
        dev_name: {
            "vm_id": int(dev_id),
            "cpu_cores": int(dev_cpu),
            "memory_mb": int(dev_mem),
            "disk_gb": int(dev_disk),
            "ip_cidr": dev_ip,
            "gateway": gateway,
            "ansible_group": "dev",
        }
    },
    "gpu_dev_vms": {},
    "tailscale_lxcs": {
        lxc_name: {
            "vm_id": int(lxc_id),
            "cpu_cores": int(lxc_cpu),
            "memory_mb": int(lxc_mem),
            "swap_mb": int(lxc_swap),
            "disk_gb": int(lxc_disk),
            "ip_cidr": lxc_ip,
            "gateway": gateway,
            "datastore_id": "local-lvm",
            "template_file_id": lxc_template,
            "ostype": "debian",
            "unprivileged": False,
            "enable_tun_passthrough": False,
        }
    },
}
with open(path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(path)
PY

  cat >"$ANSIBLE_DIR/group_vars/proxmox_hosts.yml" <<EOF
# Host-side Proxmox automation for Tailscale utility LXC containers.
# Generated/normalized by scripts/rebuild_lab_profile.sh for the lab profile.

tailscale_lxc_host_require_existing: false

tailscale_lxc_host_containers:
  ${LXC_TARGET}:
    vm_id: ${LXC_ID}
    template_storage: local
    template_file: ${LXC_TEMPLATE_FILE}
    restart_on_raw_config_change: true
    raw_config_lines:
      - regexp: '^features:.*$'
        line: 'features: keyctl=1,nesting=1'
      - regexp: '^lxc\.mount\.entry:\s+/dev/net/tun\b.*$'
        line: 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file'
      - regexp: '^lxc\.apparmor\.profile:.*$'
        line: 'lxc.apparmor.profile: unconfined'
      - regexp: '^lxc\.cgroup2\.devices\.allow:.*$'
        line: 'lxc.cgroup2.devices.allow: a'
      - regexp: '^lxc\.cap\.drop:.*$'
        line: 'lxc.cap.drop: '
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: required command not found: $1" >&2; exit 1; }
}

bootstrap_dev_vm_qga_if_ssh_ready() {
  say "Bootstrap dev VM QEMU guest agent when SSH is ready"
  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$DEV_VM_IP" >/dev/null 2>&1 || true

  for attempt in $(seq 1 30); do
    if ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -i "$ANSIBLE_SSH_KEY_FILE" "${ci_user:-ubuntu}@${DEV_VM_IP}"       'cloud-init status --wait && sudo apt-get update && sudo apt-get install -y qemu-guest-agent && sudo systemctl start qemu-guest-agent && systemctl is-active qemu-guest-agent'; then
      return 0
    fi
    echo "waiting for dev VM SSH/QGA bootstrap $attempt/30"
    sleep 10
  done

  echo "warning: dev VM SSH/QGA bootstrap did not complete before import; continuing to existing-state checks" >&2
}

ensure_tofu_state_for_existing_lab_guests() {
  say "Ensure OpenTofu state tracks existing lab-profile guests"
  cd "$TOFU_DIR"

  local dev_addr="proxmox_virtual_environment_vm.dev[\"${DEV_VM_TARGET}\"]"
  local lxc_addr="proxmox_virtual_environment_container.tailscale_lxc[\"${LXC_TARGET}\"]"

  if ssh "$LAB_PROXMOX_SSH_HOST" "qm status ${DEV_VM_ID} >/dev/null 2>&1"; then
    if ! tofu state list | grep -Fq "$dev_addr"; then
      echo "Importing existing VM ${DEV_VM_ID} as ${DEV_VM_TARGET} after partial/timed-out apply."
      tofu import "$dev_addr" "pve/${DEV_VM_ID}"
    fi
  fi

  if ssh "$LAB_PROXMOX_SSH_HOST" "pct status ${LXC_ID} >/dev/null 2>&1"; then
    if ! tofu state list | grep -Fq "$lxc_addr"; then
      echo "Importing existing CT ${LXC_ID} as ${LXC_TARGET} after partial/timed-out apply."
      tofu import "$lxc_addr" "pve/${LXC_ID}"
    fi
  fi
}

wait_for_ansible_ssh() {
  say "Wait for lab guest SSH readiness"
  cd "$REPO_ROOT"
  for group in dev tailscale_lxc; do
    for attempt in $(seq 1 30); do
      if ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$ANSIBLE_DIR/inventory/hosts.ini" "$group" -m ping >/tmp/lab-${group}-ping.out 2>/tmp/lab-${group}-ping.err; then
        cat /tmp/lab-${group}-ping.out
        break
      fi
      if [[ "$attempt" -eq 30 ]]; then
        echo "error: Ansible SSH did not become ready for group $group" >&2
        cat /tmp/lab-${group}-ping.err >&2 || true
        exit 1
      fi
      echo "waiting for $group SSH $attempt/30"
      sleep 10
    done
  done
}

say "Lab profile"
echo "repo=$REPO_ROOT"
echo "proxmox_ssh_host=$LAB_PROXMOX_SSH_HOST"
echo "proxmox_host_inventory=$PROXMOX_HOST_INVENTORY"
echo "dev_vm=$DEV_VM_TARGET vmid=$DEV_VM_ID ip=$DEV_VM_IP_CIDR cpu_cores=$DEV_VM_CPU_CORES"
echo "tailscale_lxc=$LXC_TARGET ctid=$LXC_ID ip=$LXC_IP_CIDR"
echo "gpu_dev=gpu-dev-01 EXCLUDED"
echo "apply=$APPLY destroy_existing=$DESTROY_EXISTING full_dev=$FULL_DEV tofu_apply_timeout_seconds=$TOFU_APPLY_TIMEOUT_SECONDS"

say "Prerequisite checks"
require_cmd tofu
require_cmd ansible-playbook
require_cmd python3
require_cmd ssh
[[ -f "$TOFU_DIR/proxmox.env" ]] || { echo "error: missing $TOFU_DIR/proxmox.env" >&2; exit 1; }
[[ -f "$TOFU_DIR/terraform.tfvars" ]] || { echo "error: missing $TOFU_DIR/terraform.tfvars" >&2; exit 1; }
[[ -f "$ANSIBLE_DIR/group_vars/tailscale_lxc.yml" ]] || { echo "error: missing $ANSIBLE_DIR/group_vars/tailscale_lxc.yml" >&2; exit 1; }

if grep -q '<REPLACE_ME>' "$TOFU_DIR/proxmox.env" "$TOFU_DIR/terraform.tfvars" "$ANSIBLE_DIR/group_vars/tailscale_lxc.yml"; then
  echo "error: private execution files still contain <REPLACE_ME>" >&2
  exit 1
fi

write_lab_profile_overrides

if grep -q 'gpu-dev-01' "$TOFU_DIR/terraform.tfvars"; then
  echo "note: gpu-dev-01 exists in tfvars but is excluded because this script writes $LAB_TFVARS with gpu_dev_vms={}."
fi

say "Syntax checks"
run python3 -m py_compile "$REPO_ROOT/scripts/render_inventory.py"
run bash -n "$0"
run ansible-playbook --syntax-check -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site-lab-profile.yml"
run ansible-playbook --syntax-check -i "$PROXMOX_HOST_INVENTORY" "$ANSIBLE_DIR/site-tailscale-lxc-host.yml"

cd "$TOFU_DIR"
set -a
# shellcheck disable=SC1091
. ./proxmox.env
set +a

say "OpenTofu init/validate"
run tofu init -input=false
run tofu validate

if [[ "$SKIP_HOST_PREFLIGHT" -ne 1 ]]; then
  say "Proxmox-host preflight for Tailscale LXC"
  cd "$REPO_ROOT"
  if [[ "$APPLY" -eq 1 ]]; then
    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "$PROXMOX_HOST_INVENTORY" "$ANSIBLE_DIR/site-tailscale-lxc-host.yml" | redact
  else
    echo "Plan/check mode: running Proxmox-host preflight in Ansible --check mode."
    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook --check -i "$PROXMOX_HOST_INVENTORY" "$ANSIBLE_DIR/site-tailscale-lxc-host.yml" | redact
  fi
  cd "$TOFU_DIR"
fi

if [[ "$DESTROY_EXISTING" -eq 1 ]]; then
  say "Destroy existing lab-profile guests on $LAB_PROXMOX_SSH_HOST"
  run ssh "$LAB_PROXMOX_SSH_HOST" "set -e; if qm status ${DEV_VM_ID} >/dev/null 2>&1; then qm stop ${DEV_VM_ID} --skiplock 1 || true; qm destroy ${DEV_VM_ID} --purge 1; fi; if pct status ${LXC_ID} >/dev/null 2>&1; then pct stop ${LXC_ID} --skiplock 1 || true; pct destroy ${LXC_ID} --purge 1; fi; qm status ${DEV_VM_ID} 2>/dev/null || echo VM_${DEV_VM_ID}_absent; pct status ${LXC_ID} 2>/dev/null || echo CT_${LXC_ID}_absent"
fi

say "OpenTofu plan: lab profile only"
PLAN_ARGS=(tofu plan -input=false -out="$PLAN_FILE")
for target in "${TOFU_TARGETS[@]}"; do
  PLAN_ARGS+=( -target="$target" )
done
"${PLAN_ARGS[@]}" | redact

if [[ "$APPLY" -ne 1 ]]; then
  echo
  echo "Plan/check mode complete. Re-run with --apply to create/update dev-00 and tailscale-rulab."
  echo "Add --destroy-existing only when intentionally proving clean rebuild."
  exit 0
fi

say "OpenTofu apply: lab profile only"
set +e
timeout "$TOFU_APPLY_TIMEOUT_SECONDS" tofu apply -input=false -auto-approve "$PLAN_FILE" | redact
TOFU_APPLY_RC=${PIPESTATUS[0]}
set -e

if [[ "$TOFU_APPLY_RC" -ne 0 ]]; then
  echo "warning: OpenTofu apply exited with rc=$TOFU_APPLY_RC."
  if [[ "$TOFU_APPLY_RC" -eq 124 ]]; then
    echo "OpenTofu apply hit TOFU_APPLY_TIMEOUT_SECONDS=$TOFU_APPLY_TIMEOUT_SECONDS, usually while waiting for first-boot QEMU guest agent/network data."
  fi
  echo "This can happen on a clean lab rebuild when the cloned VM lacks a running QEMU guest agent before Ansible installs it."
  echo "Continuing only if the targeted lab guests exist on Proxmox."
  ssh "$LAB_PROXMOX_SSH_HOST" "qm status ${DEV_VM_ID} && pct status ${LXC_ID}"
fi

say "Enable QEMU guest-agent device for dev VM before Ansible"
ssh "$LAB_PROXMOX_SSH_HOST" "qm status ${DEV_VM_ID} >/dev/null 2>&1 && qm set ${DEV_VM_ID} --agent enabled=1,fstrim_cloned_disks=0,type=virtio >/dev/null || true"
bootstrap_dev_vm_qga_if_ssh_ready
ensure_tofu_state_for_existing_lab_guests

if [[ "$SKIP_HOST_PREFLIGHT" -ne 1 ]]; then
  say "Proxmox-host post-create LXC config"
  cd "$REPO_ROOT"
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "$PROXMOX_HOST_INVENTORY" "$ANSIBLE_DIR/site-tailscale-lxc-host.yml" | redact
fi

say "Render Ansible inventory"
cd "$REPO_ROOT"
run python3 scripts/render_inventory.py

if [[ "$SKIP_ANSIBLE" -eq 1 ]]; then
  echo "Skipping Ansible configuration (--skip-ansible)."
  exit 0
fi

wait_for_ansible_ssh

say "Configure lab profile"
if [[ "$FULL_DEV" -eq 1 ]]; then
  echo "Using full dev play; requires fresh guest Tailscale/GitHub/repo credentials."
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site.yml" --limit 'dev,tailscale_lxc' | redact
else
  echo "Using lab profile play; gpu_dev excluded and dev guest Tailscale/GitHub workspace roles skipped."
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site-lab-profile.yml" | redact
fi

say "OpenTofu post-Ansible drift check"
cd "$TOFU_DIR"
POST_PLAN_ARGS=(tofu plan -input=false -detailed-exitcode)
for target in "${TOFU_TARGETS[@]}"; do
  POST_PLAN_ARGS+=( -target="$target" )
done
set +e
"${POST_PLAN_ARGS[@]}" | redact
POST_PLAN_RC=${PIPESTATUS[0]}
set -e
case "$POST_PLAN_RC" in
  0) echo "OpenTofu post-Ansible plan is clean." ;;
  2) echo "error: OpenTofu post-Ansible plan still has drift." >&2; exit 2 ;;
  *) echo "error: OpenTofu post-Ansible plan failed with rc=$POST_PLAN_RC." >&2; exit "$POST_PLAN_RC" ;;
esac

cd "$REPO_ROOT"

say "Final verification"
ssh "$LAB_PROXMOX_SSH_HOST" "set -e; qm status 110; pct status 100; pct exec 100 -- bash -lc 'systemctl is-active tailscaled; ls -l /dev/net/tun; sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding; iptables-save -t nat | grep -E '\''192\\.168\\.1|192\\.168\\.2|NETMAP|MASQUERADE'\''; tailscale debug prefs | grep -A5 AdvertiseRoutes; tailscale status --json > /tmp/tailscale-status.json'; pct exec 100 -- python3 - <<'PY'
import json
j=json.load(open('/tmp/tailscale-status.json'))
s=j.get('Self') or {}
print('BackendState=' + str(j.get('BackendState')))
print('DNSName=' + str(s.get('DNSName')))
print('PrimaryRoutes=' + str(s.get('PrimaryRoutes')))
print('AllowedIPs=' + str(s.get('AllowedIPs')))
PY"

echo

echo "Lab profile rebuild finished. If PrimaryRoutes is None, approve 192.168.2.0/24 for the recreated Tailscale node or configure ACL autoApprovers."
