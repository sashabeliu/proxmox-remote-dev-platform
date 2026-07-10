#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/validate_repo_safety.sh [--mode repo|deploy]

Modes:
  --mode repo    Verify the repository is safe to commit/push. This mode expects
                 tracked sanitized secret files to still contain placeholders.
  --mode deploy  Verify a private working copy is ready to execute. This mode
                 expects placeholders to be replaced in execution-critical files.
EOF
}

MODE="repo"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || { echo "error: --mode requires a value" >&2; usage; exit 2; }
      MODE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "repo" && "$MODE" != "deploy" ]]; then
  echo "error: mode must be 'repo' or 'deploy'" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

failures=0

say() { printf '%s\n' "$*"; }
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

require_exists() {
  local path="$1"
  if [[ -f "$path" ]]; then
    pass "file exists: $path"
  else
    fail "missing required file: $path"
  fi
}

require_exact_line() {
  local path="$1"
  local expected="$2"
  if grep -Fxq "$expected" "$path"; then
    pass "$path contains expected placeholder line"
  else
    fail "$path does not contain expected line: $expected"
  fi
}

require_no_placeholder() {
  local path="$1"
  if grep -q '<REPLACE_ME>' "$path"; then
    fail "$path still contains <REPLACE_ME>"
  else
    pass "$path has no <REPLACE_ME> placeholders"
  fi
}

check_literal_secret_patterns() {
  local matches=""
  matches="$(git grep -nI -E 'BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|tskey-[A-Za-z0-9-]{20,}' -- . || true)"
  if [[ -n "$matches" ]]; then
    fail "high-confidence secret-like material detected in tracked files"
    printf '%s\n' "$matches" >&2
  else
    pass "no high-confidence secret patterns detected in tracked files"
  fi
}

check_state_artifacts() {
  local state_hits=""
  state_hits="$(find . -path './.git' -prune -o -path './.terraform' -prune -o \( -name '*.tfstate' -o -name '*.tfstate.*' -o -path '*/.terraform/*' \) -print)"
  if [[ -n "$state_hits" ]]; then
    fail "forbidden Terraform/OpenTofu state artifacts present in repo working tree"
    printf '%s\n' "$state_hits" >&2
  else
    pass "no Terraform/OpenTofu state artifacts present in repo working tree"
  fi
}

check_crlf_risk() {
  local pybin=""
  if command -v python >/dev/null 2>&1; then
    pybin="python"
  elif command -v python3 >/dev/null 2>&1; then
    pybin="python3"
  else
    fail "python or python3 is required for CRLF validation"
    return
  fi

  local files=""
  files="$($pybin - <<'PY'
from pathlib import Path

root = Path('.')
lf_exts = {'.sh', '.py', '.tf', '.tfvars', '.hcl', '.yml', '.yaml', '.md', '.env', '.ini', '.j2'}
lf_names = {'.gitignore', '.gitattributes'}

for path in sorted(root.rglob('*')):
    if not path.is_file():
        continue
    if '.git' in path.parts:
        continue
    if path.name not in lf_names and path.suffix.lower() not in lf_exts:
        continue
    data = path.read_bytes()
    if b'\r' in data:
        print(path.as_posix())
PY
)"
  if [[ -n "$files" ]]; then
    fail "CRLF detected in files that should stay LF"
    printf '%s\n' "$files" >&2
  else
    pass "no CRLF detected in LF-normalized file types"
  fi
}

say "Running repo safety validation in mode: $MODE"

required_files=(
  ".gitattributes"
  "tofu/proxmox.env"
  "tofu/terraform.tfvars"
  "ansible/group_vars/all.yml"
  "ansible/group_vars/dev.yml"
  "ansible/group_vars/gpu_dev.yml"
)
for file in "${required_files[@]}"; do
  require_exists "$file"
done

if [[ "$MODE" == "repo" ]]; then
  require_exact_line "tofu/proxmox.env" 'export PROXMOX_VE_API_TOKEN="<REPLACE_ME>"'
  require_exact_line "ansible/group_vars/all.yml" 'tailscale_auth_key: "<REPLACE_ME>"'
  require_exact_line "ansible/group_vars/dev.yml" 'code_server_password: "<REPLACE_ME>"'
  require_exact_line "ansible/group_vars/gpu_dev.yml" 'code_server_password: "<REPLACE_ME>"'
else
  require_no_placeholder "tofu/proxmox.env"
  require_no_placeholder "tofu/terraform.tfvars"
  require_no_placeholder "ansible/group_vars/all.yml"
  require_no_placeholder "ansible/group_vars/dev.yml"
  require_no_placeholder "ansible/group_vars/gpu_dev.yml"
fi

check_literal_secret_patterns
check_state_artifacts
check_crlf_risk

if [[ "$failures" -gt 0 ]]; then
  say "Validation finished with $failures failure(s)."
  exit 1
fi

say "Validation finished successfully."
