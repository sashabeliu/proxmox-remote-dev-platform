#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/rebuild_from_zero_lab.sh [--config <site.yml> | --proxmox-host <host-or-ip>] [options]

Bootstrap a fresh/minimal Proxmox host. In handoff mode, the external runner creates
VM101 ansible-control, prepares it, copies a materialized execution tree there, then
VM101 runs the remaining non-GPU lab deployment.

Default is check/plan mode: no destructive cleanup and no OpenTofu apply.

Options:
  --proxmox-host <host>              Required. Root SSH target for the Proxmox host from the external runner.
  --post-wipe-proxmox-host <host>    Required with --wipe-existing-guests-and-templates. Root SSH target that remains reachable
                                     after all VMs/CTs are destroyed. Do not point this at a route provided by CT100/Tailscale.
  --apply                            Apply host bootstrap/provisioning. Without this, use Ansible --check and OpenTofu plan only.
  --wipe-existing-guests-and-templates
                                     DANGEROUS: destroy all VMs, all CTs, and local LXC templates on the Proxmox host. Requires --apply.
  --destroy-existing                 Pass through to lab profile; destroys only VM110 and CT100. Requires --apply.
  --private-bundle-root <path>       Materialize legacy private bundle into this working tree before running.
  --config <path>                    Materialize runtime files from one local site.yml config. Preferred current workflow.
  --bootstrap-runner                 Install local runner dependencies first; Debian/Ubuntu runner only.
  --with-provider-mirror             When bootstrapping runner/control VM, install bpg/proxmox provider mirror.
  --manage-apt-repos                 Let Proxmox bootstrap manage no-subscription/enterprise apt repo files.
  --create-template                  Create template VM9000 if missing.
  --recreate-template                Recreate template VM9000 even if present. Requires --create-template and --apply.
  --manage-api-token                 Create/check Proxmox API user/token on host.
  --pull-generated-token             If host generated /root/proxmox-api-token.env, copy it into tofu/proxmox.env when local file has <REPLACE_ME>.
  --create-control-vm                Generate private control-vm auto.tfvars and create/plan VM101 ansible-control.
  --handoff-to-control               After VM101 is ready, copy this materialized execution tree to it and run lab deployment from VM101. Requires --create-control-vm --apply.
  --control-vm-name <name>           Default: ansible-control
  --control-vm-id <id>               Default: 101
  --control-vm-ip-cidr <cidr>        Default: 192.168.1.211/24
  --control-vm-gateway <ip>          Default: 192.168.1.1
  --control-vm-cpu-type <type>       Default: x86-64-v2
  --control-vm-ansible-host <ip>     SSH address from external runner via ProxyJump. Default: IP from --control-vm-ip-cidr.
  --control-proxmox-ssh-host <host>  Proxmox SSH host/alias to write into VM101 ~/.ssh/config. Default: --proxmox-host.
  --control-proxmox-api-endpoint <url>
                                   Proxmox API endpoint to write into VM101 tofu config after handoff. Default: https://<control-proxmox-ssh-host>:8006/.
  --skip-lab-profile                 Only run host/control bootstrap; do not deploy VM110/CT100.
  --full-dev                         Pass through to rebuild_lab_profile.sh --full-dev.
  -h, --help                         Show this help.

Manual prerequisite before this script:
  Proxmox is installed, root SSH works from the external runner, and management networking is reachable.
EOF
}

PROXMOX_HOST=""
POST_WIPE_PROXMOX_HOST=""
APPLY=0
WIPE_EXISTING_GUESTS_AND_TEMPLATES=0
DESTROY_EXISTING=0
PRIVATE_BUNDLE_ROOT=""
SITE_CONFIG=""
BOOTSTRAP_RUNNER=0
WITH_PROVIDER_MIRROR=0
MANAGE_APT_REPOS=0
CREATE_TEMPLATE=0
RECREATE_TEMPLATE=0
MANAGE_API_TOKEN=0
PULL_GENERATED_TOKEN=0
CREATE_CONTROL_VM=0
HANDOFF_TO_CONTROL=0
CONTROL_VM_NAME=""
CONTROL_VM_ID=""
CONTROL_VM_IP_CIDR=""
CONTROL_VM_GATEWAY=""
CONTROL_VM_CPU_TYPE=""
CONTROL_VM_ANSIBLE_HOST=""
CONTROL_PROXMOX_SSH_HOST=""
CONTROL_PROXMOX_API_ENDPOINT=""
SKIP_LAB_PROFILE=0
FULL_DEV=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proxmox-host) [[ $# -ge 2 ]] || { echo "error: --proxmox-host requires value" >&2; exit 2; }; PROXMOX_HOST="$2"; shift 2 ;;
    --post-wipe-proxmox-host) [[ $# -ge 2 ]] || { echo "error: --post-wipe-proxmox-host requires value" >&2; exit 2; }; POST_WIPE_PROXMOX_HOST="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --wipe-existing-guests-and-templates) WIPE_EXISTING_GUESTS_AND_TEMPLATES=1; shift ;;
    --destroy-existing) DESTROY_EXISTING=1; shift ;;
    --private-bundle-root) [[ $# -ge 2 ]] || { echo "error: --private-bundle-root requires value" >&2; exit 2; }; PRIVATE_BUNDLE_ROOT="$2"; shift 2 ;;
    --config) [[ $# -ge 2 ]] || { echo "error: --config requires value" >&2; exit 2; }; SITE_CONFIG="$2"; shift 2 ;;
    --bootstrap-runner) BOOTSTRAP_RUNNER=1; shift ;;
    --with-provider-mirror) WITH_PROVIDER_MIRROR=1; shift ;;
    --manage-apt-repos) MANAGE_APT_REPOS=1; shift ;;
    --create-template) CREATE_TEMPLATE=1; shift ;;
    --recreate-template) RECREATE_TEMPLATE=1; shift ;;
    --manage-api-token) MANAGE_API_TOKEN=1; shift ;;
    --pull-generated-token) PULL_GENERATED_TOKEN=1; shift ;;
    --create-control-vm) CREATE_CONTROL_VM=1; shift ;;
    --handoff-to-control) HANDOFF_TO_CONTROL=1; shift ;;
    --control-vm-name) [[ $# -ge 2 ]] || { echo "error: --control-vm-name requires value" >&2; exit 2; }; CONTROL_VM_NAME="$2"; shift 2 ;;
    --control-vm-id) [[ $# -ge 2 ]] || { echo "error: --control-vm-id requires value" >&2; exit 2; }; CONTROL_VM_ID="$2"; shift 2 ;;
    --control-vm-ip-cidr) [[ $# -ge 2 ]] || { echo "error: --control-vm-ip-cidr requires value" >&2; exit 2; }; CONTROL_VM_IP_CIDR="$2"; shift 2 ;;
    --control-vm-gateway) [[ $# -ge 2 ]] || { echo "error: --control-vm-gateway requires value" >&2; exit 2; }; CONTROL_VM_GATEWAY="$2"; shift 2 ;;
    --control-vm-cpu-type) [[ $# -ge 2 ]] || { echo "error: --control-vm-cpu-type requires value" >&2; exit 2; }; CONTROL_VM_CPU_TYPE="$2"; shift 2 ;;
    --control-vm-ansible-host) [[ $# -ge 2 ]] || { echo "error: --control-vm-ansible-host requires value" >&2; exit 2; }; CONTROL_VM_ANSIBLE_HOST="$2"; shift 2 ;;
    --control-proxmox-ssh-host) [[ $# -ge 2 ]] || { echo "error: --control-proxmox-ssh-host requires value" >&2; exit 2; }; CONTROL_PROXMOX_SSH_HOST="$2"; shift 2 ;;
    --control-proxmox-api-endpoint) [[ $# -ge 2 ]] || { echo "error: --control-proxmox-api-endpoint requires value" >&2; exit 2; }; CONTROL_PROXMOX_API_ENDPOINT="$2"; shift 2 ;;
    --skip-lab-profile) SKIP_LAB_PROFILE=1; shift ;;
    --full-dev) FULL_DEV=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANSIBLE_DIR="$REPO_ROOT/ansible"
TOFU_DIR="$REPO_ROOT/tofu"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
PROXMOX_INVENTORY="$TMP_DIR/proxmox-hosts.ini"
PROXMOX_EXTRA_VARS="$TMP_DIR/proxmox-bootstrap-vars.yml"
CONTROL_INVENTORY="$TMP_DIR/control.ini"
CONTROL_VM_TFVARS="$TOFU_DIR/control-vm.auto.tfvars.json"
SITE_ENV="$TMP_DIR/site-config.env"

if [[ -n "$SITE_CONFIG" && -n "$PRIVATE_BUNDLE_ROOT" ]]; then
  echo "error: use either --config or --private-bundle-root, not both" >&2
  exit 2
fi

if [[ -n "$SITE_CONFIG" ]]; then
  echo
  echo "== Materialize local site config =="
  python3 "$SCRIPT_DIR/materialize_site_config.py" --config "$SITE_CONFIG" --repo-root "$REPO_ROOT" --env-out "$SITE_ENV"
  # shellcheck disable=SC1090
  . "$SITE_ENV"
  ANSIBLE_KEY_FILE="${ANSIBLE_KEY_FILE:-${SITE_ANSIBLE_KEY_FILE:-}}"
  PROXMOX_HOST="${PROXMOX_HOST:-${SITE_PROXMOX_HOST:-}}"
  POST_WIPE_PROXMOX_HOST="${POST_WIPE_PROXMOX_HOST:-${SITE_POST_WIPE_PROXMOX_HOST:-}}"
  CONTROL_PROXMOX_SSH_HOST="${CONTROL_PROXMOX_SSH_HOST:-${SITE_CONTROL_PROXMOX_SSH_HOST:-}}"
  CONTROL_PROXMOX_API_ENDPOINT="${CONTROL_PROXMOX_API_ENDPOINT:-${SITE_CONTROL_PROXMOX_API_ENDPOINT:-}}"
  CONTROL_VM_NAME="${CONTROL_VM_NAME:-${SITE_CONTROL_VM_NAME:-ansible-control}}"
  CONTROL_VM_ID="${CONTROL_VM_ID:-${SITE_CONTROL_VM_ID:-101}}"
  CONTROL_VM_IP_CIDR="${CONTROL_VM_IP_CIDR:-${SITE_CONTROL_VM_IP_CIDR:-192.168.1.211/24}}"
  CONTROL_VM_GATEWAY="${CONTROL_VM_GATEWAY:-${SITE_CONTROL_VM_GATEWAY:-192.168.1.1}}"
  CONTROL_VM_CPU_TYPE="${CONTROL_VM_CPU_TYPE:-${SITE_CONTROL_VM_CPU_TYPE:-x86-64-v2}}"
  export TOFU_APPLY_TIMEOUT_SECONDS="${TOFU_APPLY_TIMEOUT_SECONDS:-${SITE_TOFU_APPLY_TIMEOUT_SECONDS:-}}"
fi

[[ -n "$PROXMOX_HOST" ]] || { echo "error: --proxmox-host or config.proxmox.pre_wipe_ssh_host is required" >&2; usage; exit 2; }
if [[ "$WIPE_EXISTING_GUESTS_AND_TEMPLATES" -eq 1 && "$APPLY" -ne 1 ]]; then
  echo "error: --wipe-existing-guests-and-templates requires --apply" >&2
  exit 2
fi
if [[ "$WIPE_EXISTING_GUESTS_AND_TEMPLATES" -eq 1 && -z "$POST_WIPE_PROXMOX_HOST" ]]; then
  echo "error: --wipe-existing-guests-and-templates requires --post-wipe-proxmox-host or config.proxmox.post_wipe_ssh_host" >&2
  echo "The post-wipe SSH endpoint must be reachable without any Proxmox VM/CT/Tailscale LXC running." >&2
  exit 2
fi
if [[ "$DESTROY_EXISTING" -eq 1 && "$APPLY" -ne 1 ]]; then
  echo "error: --destroy-existing requires --apply" >&2
  exit 2
fi
if [[ "$RECREATE_TEMPLATE" -eq 1 && ( "$CREATE_TEMPLATE" -ne 1 || "$APPLY" -ne 1 ) ]]; then
  echo "error: --recreate-template requires --create-template --apply" >&2
  exit 2
fi
if [[ "$HANDOFF_TO_CONTROL" -eq 1 && ( "$CREATE_CONTROL_VM" -ne 1 || "$APPLY" -ne 1 ) ]]; then
  echo "error: --handoff-to-control requires --create-control-vm --apply" >&2
  exit 2
fi

CONTROL_VM_NAME="${CONTROL_VM_NAME:-ansible-control}"
CONTROL_VM_ID="${CONTROL_VM_ID:-101}"
CONTROL_VM_IP_CIDR="${CONTROL_VM_IP_CIDR:-192.168.1.211/24}"
CONTROL_VM_GATEWAY="${CONTROL_VM_GATEWAY:-192.168.1.1}"
CONTROL_VM_CPU_TYPE="${CONTROL_VM_CPU_TYPE:-x86-64-v2}"
CONTROL_VM_ANSIBLE_HOST="${CONTROL_VM_ANSIBLE_HOST:-${CONTROL_VM_IP_CIDR%%/*}}"
CONTROL_PROXMOX_SSH_HOST="${CONTROL_PROXMOX_SSH_HOST:-$PROXMOX_HOST}"
CONTROL_PROXMOX_API_ENDPOINT="${CONTROL_PROXMOX_API_ENDPOINT:-https://${CONTROL_PROXMOX_SSH_HOST}:8006/}"
ANSIBLE_KEY_FILE="${ANSIBLE_KEY_FILE:-$HOME/.ssh/ansible_ed25519}"
ANSIBLE_KEY_FILE_ON_CONTROL="/home/ubuntu/.ssh/ansible_ed25519"
CONTROL_REPO_PATH="/home/ubuntu/proxmox-remote-dev-platform-private"
CONTROL_SSH_ARGS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o "ProxyJump=root@${PROXMOX_HOST}" -i "$ANSIBLE_KEY_FILE")
CONTROL_SCP_ARGS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o "ProxyJump=root@${PROXMOX_HOST}" -i "$ANSIBLE_KEY_FILE")
TOFU_CONTROL_TARGET="proxmox_virtual_environment_vm.control[\"${CONTROL_VM_NAME}\"]"

redact() { sed -E 's/tskey-[A-Za-z0-9-]+/[REDACTED_TSKEY]/g; s/(PROXMOX_VE_API_TOKEN=)[^[:space:]]+/\1[REDACTED]/g; s/(token|secret|password|authkey|auth_key)[^[:space:]]*/[REDACTED]/Ig'; }
say() { printf '\n== %s ==\n' "$*"; }
run() { printf '+ %q ' "$@"; printf '\n'; "$@"; }
bool_text() { if [[ "$1" -eq 1 ]]; then printf 'true'; else printf 'false'; fi; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "error: required command not found: $1" >&2; exit 1; }; }

if [[ "$BOOTSTRAP_RUNNER" -eq 1 ]]; then
  say "Bootstrap local external runner"
  RUNNER_ARGS=()
  [[ "$WITH_PROVIDER_MIRROR" -eq 1 ]] && RUNNER_ARGS+=(--with-opentofu-provider-mirror)
  bash "$SCRIPT_DIR/bootstrap_control_runner.sh" "${RUNNER_ARGS[@]}"
fi

say "External runner prerequisite checks"
require_cmd ssh
require_cmd python3
if [[ "$CREATE_CONTROL_VM" -eq 1 || "$SKIP_LAB_PROFILE" -ne 1 ]]; then
  require_cmd tofu
fi
if [[ "$HANDOFF_TO_CONTROL" -eq 1 || "$SKIP_LAB_PROFILE" -ne 1 || "$CREATE_CONTROL_VM" -eq 1 ]]; then
  require_cmd ansible-playbook
fi
if [[ ! -f "$ANSIBLE_KEY_FILE" ]]; then
  echo "error: missing Ansible SSH private key: $ANSIBLE_KEY_FILE" >&2
  exit 1
fi

say "Verify direct Proxmox SSH"
run ssh -o BatchMode=yes -o ConnectTimeout=10 "$PROXMOX_HOST" 'hostname && id && pveversion'

if [[ "$WIPE_EXISTING_GUESTS_AND_TEMPLATES" -eq 1 ]]; then
  say "Verify post-wipe Proxmox SSH endpoint"
  run ssh -o BatchMode=yes -o ConnectTimeout=10 "$POST_WIPE_PROXMOX_HOST" 'hostname && id && pveversion'
fi

if [[ "$WIPE_EXISTING_GUESTS_AND_TEMPLATES" -eq 1 ]]; then
  say "DANGEROUS wipe: all Proxmox guests and local LXC templates on $PROXMOX_HOST"
  ssh "$PROXMOX_HOST" 'set -euo pipefail
    echo "Before wipe:"; qm list || true; pct list || true; pveam list local || true
    for id in $(qm list | awk "NR>1{print \$1}"); do
      echo "Destroy VM/template $id"
      qm stop "$id" --skiplock 1 2>/dev/null || true
      qm destroy "$id" --purge 1 --destroy-unreferenced-disks 1
    done
    for id in $(pct list | awk "NR>1{print \$1}"); do
      echo "Destroy CT $id"
      pct stop "$id" --skiplock 1 2>/dev/null || true
      pct destroy "$id" --purge 1
    done
    for tpl in $(pveam list local | awk "NR>1{print \$1}"); do
      echo "Remove LXC template $tpl"
      pveam remove "$tpl" || true
    done
    echo "After wipe:"; qm list || true; pct list || true; pveam list local || true
  '
  PROXMOX_HOST="$POST_WIPE_PROXMOX_HOST"
  CONTROL_SSH_ARGS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o "ProxyJump=root@${PROXMOX_HOST}" -i "$ANSIBLE_KEY_FILE")
  CONTROL_SCP_ARGS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o "ProxyJump=root@${PROXMOX_HOST}" -i "$ANSIBLE_KEY_FILE")
  say "Verify Proxmox SSH after destructive wipe"
  run ssh -o BatchMode=yes -o ConnectTimeout=10 "$PROXMOX_HOST" 'hostname && id && pveversion'
fi

say "Prepare generated Proxmox inventory"
cat >"$PROXMOX_INVENTORY" <<EOF
[proxmox_hosts]
zero-proxmox ansible_host=${PROXMOX_HOST}

[all:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
EOF
cat "$PROXMOX_INVENTORY"

LOCAL_PUBKEY=""
if [[ -f "${ANSIBLE_KEY_FILE}.pub" ]]; then
  LOCAL_PUBKEY="$(tr -d '\r\n' < "${ANSIBLE_KEY_FILE}.pub")"
elif [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
  LOCAL_PUBKEY="$(tr -d '\r\n' < "$HOME/.ssh/id_ed25519.pub")"
fi
if [[ -z "$LOCAL_PUBKEY" ]]; then
  echo "error: could not find public key for cloud-init/root authorized_keys. Expected ${ANSIBLE_KEY_FILE}.pub" >&2
  exit 1
fi

cat >"$PROXMOX_EXTRA_VARS" <<EOF
proxmox_host_manage_apt_repos: $(bool_text "$MANAGE_APT_REPOS")
proxmox_host_template_create: $(bool_text "$CREATE_TEMPLATE")
proxmox_host_template_recreate: $(bool_text "$RECREATE_TEMPLATE")
proxmox_host_api_manage: $(bool_text "$MANAGE_API_TOKEN")
proxmox_host_local_access_pubkey: "${LOCAL_PUBKEY}"
proxmox_host_root_authorized_keys:
  - "${LOCAL_PUBKEY}"
EOF

if [[ -n "$PRIVATE_BUNDLE_ROOT" ]]; then
  say "Materialize private config"
  bash "$SCRIPT_DIR/materialize_private_config.sh" --repo-root "$REPO_ROOT" --bundle-root "$PRIVATE_BUNDLE_ROOT"
fi

if [[ "$CREATE_CONTROL_VM" -eq 1 ]]; then
  say "Generate private control VM tfvars"
  python3 - "$CONTROL_VM_TFVARS" "$CONTROL_VM_NAME" "$CONTROL_VM_ID" "$CONTROL_VM_IP_CIDR" "$CONTROL_VM_GATEWAY" "$CONTROL_VM_CPU_TYPE" <<'PY'
import json, sys
path, name, vmid, ip_cidr, gateway, cpu_type = sys.argv[1:]
data = {
    "control_vms": {
        name: {
            "vm_id": int(vmid),
            "cpu_cores": 2,
            "memory_mb": 2048,
            "disk_gb": 20,
            "ip_cidr": ip_cidr,
            "gateway": gateway,
            "cpu_type": cpu_type,
        }
    }
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(path)
PY
fi

say "Proxmox host bootstrap"
ANSIBLE_ARGS=(-i "$PROXMOX_INVENTORY" -e "@$PROXMOX_EXTRA_VARS" "$ANSIBLE_DIR/site-proxmox-bootstrap.yml")
if [[ "$APPLY" -eq 1 ]]; then
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook "${ANSIBLE_ARGS[@]}" | redact
else
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook --check "${ANSIBLE_ARGS[@]}" | redact
fi

if [[ "$APPLY" -eq 1 && "$PULL_GENERATED_TOKEN" -eq 1 ]]; then
  if [[ -f "$TOFU_DIR/proxmox.env" ]] && grep -q '<REPLACE_ME>' "$TOFU_DIR/proxmox.env"; then
    say "Pull generated Proxmox API token env into materialized execution context"
    ssh "$PROXMOX_HOST" 'test -s /root/proxmox-api-token.env && cat /root/proxmox-api-token.env' >"$TOFU_DIR/proxmox.env"
    chmod 600 "$TOFU_DIR/proxmox.env"
  fi
fi

if [[ "$CREATE_CONTROL_VM" -eq 1 ]]; then
  say "OpenTofu create/plan control VM"
  cd "$TOFU_DIR"
  set -a
  # shellcheck disable=SC1091
  . ./proxmox.env
  set +a
  run tofu init -input=false
  run tofu validate
  if [[ "$APPLY" -eq 1 ]]; then
    set +e
    tofu apply -input=false -auto-approve -target="$TOFU_CONTROL_TARGET" | redact
    CONTROL_TOFU_RC=${PIPESTATUS[0]}
    set -e
    if [[ "$CONTROL_TOFU_RC" -ne 0 ]]; then
      echo "warning: control VM OpenTofu apply exited rc=$CONTROL_TOFU_RC; continuing only if VM ${CONTROL_VM_ID} exists."
      ssh "$PROXMOX_HOST" "qm status ${CONTROL_VM_ID}"
    fi
  else
    tofu plan -input=false -target="$TOFU_CONTROL_TARGET" | redact
  fi
  cd "$REPO_ROOT"
fi

if [[ "$HANDOFF_TO_CONTROL" -eq 1 ]]; then
  say "Prepare external inventory for VM101 through Proxmox ProxyJump"
  cat >"$CONTROL_INVENTORY" <<EOF
[control]
${CONTROL_VM_NAME} ansible_host=${CONTROL_VM_ANSIBLE_HOST}

[control:vars]
ansible_ssh_common_args='-o ProxyJump=root@${PROXMOX_HOST} -o StrictHostKeyChecking=accept-new'

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=${ANSIBLE_KEY_FILE}
ansible_python_interpreter=/usr/bin/python3
EOF
  cat "$CONTROL_INVENTORY"

  say "Wait for VM101 SSH via Proxmox ProxyJump"
  for attempt in $(seq 1 60); do
    if ssh "${CONTROL_SSH_ARGS[@]}" "ubuntu@${CONTROL_VM_ANSIBLE_HOST}" 'hostname && id' >/tmp/control-ssh-ready.$$ 2>/tmp/control-ssh-ready.err.$$; then
      cat /tmp/control-ssh-ready.$$
      rm -f /tmp/control-ssh-ready.$$ /tmp/control-ssh-ready.err.$$
      break
    fi
    if [[ "$attempt" -eq 60 ]]; then
      echo "error: VM101 SSH did not become ready" >&2
      cat /tmp/control-ssh-ready.err.$$ >&2 || true
      exit 1
    fi
    sleep 5
  done

  say "Configure VM101 as control runner"
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "$CONTROL_INVENTORY" "$ANSIBLE_DIR/site-control-runner.yml" \
    -e "control_runner_install_provider_mirror=$(bool_text "$WITH_PROVIDER_MIRROR")" | redact

  say "Copy SSH key and materialized execution tree to VM101"
  ssh "${CONTROL_SSH_ARGS[@]}" "ubuntu@${CONTROL_VM_ANSIBLE_HOST}" 'set -e; install -d -m 700 ~/.ssh'
  scp "${CONTROL_SCP_ARGS[@]}" "$ANSIBLE_KEY_FILE" "ubuntu@${CONTROL_VM_ANSIBLE_HOST}:${ANSIBLE_KEY_FILE_ON_CONTROL}"
  if [[ -f "${ANSIBLE_KEY_FILE}.pub" ]]; then
    scp "${CONTROL_SCP_ARGS[@]}" "${ANSIBLE_KEY_FILE}.pub" "ubuntu@${CONTROL_VM_ANSIBLE_HOST}:${ANSIBLE_KEY_FILE_ON_CONTROL}.pub"
  fi
  ssh "${CONTROL_SSH_ARGS[@]}" "ubuntu@${CONTROL_VM_ANSIBLE_HOST}" "set -e; chmod 600 ${ANSIBLE_KEY_FILE_ON_CONTROL}; chmod 644 ${ANSIBLE_KEY_FILE_ON_CONTROL}.pub 2>/dev/null || true; cat >~/.ssh/config <<EOF
Host proxmox-rulab
  HostName ${CONTROL_PROXMOX_SSH_HOST}
  User root
  IdentityFile ${ANSIBLE_KEY_FILE_ON_CONTROL}
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config"

  tar --exclude='./.git' -czf - -C "$REPO_ROOT" . | \
    ssh "${CONTROL_SSH_ARGS[@]}" "ubuntu@${CONTROL_VM_ANSIBLE_HOST}" "set -e; rm -rf '${CONTROL_REPO_PATH}'; mkdir -p '${CONTROL_REPO_PATH}'; tar -xzf - -C '${CONTROL_REPO_PATH}'; chmod +x '${CONTROL_REPO_PATH}'/scripts/*.sh"

  ssh "${CONTROL_SSH_ARGS[@]}" "ubuntu@${CONTROL_VM_ANSIBLE_HOST}" "cd '${CONTROL_REPO_PATH}' && python3 - <<'PY'
from pathlib import Path
endpoint = '${CONTROL_PROXMOX_API_ENDPOINT}'
tfvars = Path('tofu/terraform.tfvars')
env = Path('tofu/proxmox.env')
tfvars.write_text('\n'.join(
    ('proxmox_endpoint = ' + repr(endpoint).replace(\"'\", '\"')) if line.startswith('proxmox_endpoint =') else line
    for line in tfvars.read_text().splitlines()
) + '\n')
env.write_text('\n'.join(
    (\"export PROXMOX_VE_ENDPOINT='\" + endpoint + \"'\") if line.startswith('export PROXMOX_VE_ENDPOINT=') else line
    for line in env.read_text().splitlines()
) + '\n')
inventory = Path('ansible/inventory/proxmox-hosts.ini')
inventory.write_text('''[proxmox_hosts]
pve ansible_host=proxmox-rulab

[all:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
''')
print('updated VM101 Proxmox API endpoint and host inventory')
PY"

  say "Handoff: run remaining lab deployment from VM101"
  if [[ "$SKIP_LAB_PROFILE" -eq 1 ]]; then
    echo "Skipping lab profile after VM101 handoff (--skip-lab-profile)."
    exit 0
  fi
  CONTROL_LAB_ARGS=(--apply)
  [[ "$DESTROY_EXISTING" -eq 1 ]] && CONTROL_LAB_ARGS+=(--destroy-existing)
  [[ "$FULL_DEV" -eq 1 ]] && CONTROL_LAB_ARGS+=(--full-dev)
  ssh "${CONTROL_SSH_ARGS[@]}" "ubuntu@${CONTROL_VM_ANSIBLE_HOST}" "cd '${CONTROL_REPO_PATH}' && LAB_PROXMOX_SSH_HOST=proxmox-rulab bash scripts/rebuild_lab_profile.sh ${CONTROL_LAB_ARGS[*]}" | redact
  say "Zero-to-lab handoff workflow complete"
  exit 0
fi

if [[ "$SKIP_LAB_PROFILE" -eq 1 ]]; then
  echo "Skipping lab profile rebuild (--skip-lab-profile)."
  exit 0
fi

say "Run non-GPU lab rebuild profile from external runner"
LAB_ARGS=()
if [[ "$APPLY" -eq 1 ]]; then
  LAB_ARGS+=(--apply)
  [[ "$DESTROY_EXISTING" -eq 1 ]] && LAB_ARGS+=(--destroy-existing)
fi
[[ "$FULL_DEV" -eq 1 ]] && LAB_ARGS+=(--full-dev)
LAB_PROXMOX_SSH_HOST="$PROXMOX_HOST" \
PROXMOX_HOST_INVENTORY="$PROXMOX_INVENTORY" \
ANSIBLE_SSH_KEY_FILE="$ANSIBLE_KEY_FILE" \
  bash "$SCRIPT_DIR/rebuild_lab_profile.sh" "${LAB_ARGS[@]}" | redact

say "Zero-to-lab workflow complete"
