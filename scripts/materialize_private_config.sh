#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/materialize_private_config.sh --bundle-root <path> [--repo-root <path>] [--dry-run] [--skip-validate]

Options:
  --bundle-root <path>  Path to the private bundle root. This may point either to:
                        (a) the repo-specific bundle root containing tofu/ and ansible/
                        (b) a parent directory containing a proxmox-remote-dev-platform/ subdir
  --repo-root <path>    Override the repo root to materialize into. Defaults to this script's repo.
  --dry-run             Print what would be copied without changing files.
  --skip-validate       Do not run deploy validation after copying.
  -h, --help            Show this help.

Environment:
  PRIVATE_BUNDLE_ROOT   Optional default for --bundle-root.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$DEFAULT_REPO_ROOT"
BUNDLE_ROOT="${PRIVATE_BUNDLE_ROOT:-}"
DRY_RUN=0
SKIP_VALIDATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-root)
      [[ $# -ge 2 ]] || { echo "error: --bundle-root requires a value" >&2; usage; exit 2; }
      BUNDLE_ROOT="$2"
      shift 2
      ;;
    --repo-root)
      [[ $# -ge 2 ]] || { echo "error: --repo-root requires a value" >&2; usage; exit 2; }
      REPO_ROOT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-validate)
      SKIP_VALIDATE=1
      shift
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

[[ -n "$BUNDLE_ROOT" ]] || { echo "error: --bundle-root or PRIVATE_BUNDLE_ROOT is required" >&2; usage; exit 2; }

canon_dir() {
  local path="$1"
  if [[ ! -d "$path" ]]; then
    echo "error: directory does not exist: $path" >&2
    exit 2
  fi
  (
    cd "$path"
    pwd
  )
}

REPO_ROOT="$(canon_dir "$REPO_ROOT")"
BUNDLE_ROOT="$(canon_dir "$BUNDLE_ROOT")"

if [[ -f "$BUNDLE_ROOT/tofu/proxmox.env" && -f "$BUNDLE_ROOT/ansible/group_vars/all.yml" ]]; then
  ACTUAL_BUNDLE_ROOT="$BUNDLE_ROOT"
else
  ACTUAL_BUNDLE_ROOT=""
  while IFS= read -r candidate; do
    if [[ -f "$candidate/tofu/proxmox.env" && -f "$candidate/ansible/group_vars/all.yml" ]]; then
      if [[ -n "$ACTUAL_BUNDLE_ROOT" ]]; then
        echo "error: multiple candidate bundle roots found under: $BUNDLE_ROOT" >&2
        echo "candidates: $ACTUAL_BUNDLE_ROOT and $candidate" >&2
        exit 2
      fi
      ACTUAL_BUNDLE_ROOT="$candidate"
    fi
  done < <(find "$BUNDLE_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)

  if [[ -z "$ACTUAL_BUNDLE_ROOT" ]]; then
    echo "error: could not find bundle files under: $BUNDLE_ROOT" >&2
    echo "expected either $BUNDLE_ROOT/tofu/... or exactly one immediate child directory with tofu/... and ansible/group_vars/..." >&2
    exit 2
  fi
fi

required_paths=(
  "tofu/proxmox.env"
  "tofu/terraform.tfvars"
  "ansible/group_vars/all.yml"
  "ansible/group_vars/dev.yml"
  "ansible/group_vars/gpu_dev.yml"
)

for rel in "${required_paths[@]}"; do
  src="$ACTUAL_BUNDLE_ROOT/$rel"
  if [[ ! -f "$src" ]]; then
    echo "error: missing required bundle file: $src" >&2
    exit 1
  fi
  if grep -q '<REPLACE_ME>' "$src"; then
    echo "error: bundle file still contains <REPLACE_ME>: $src" >&2
    exit 1
  fi
done

echo "Repo root:   $REPO_ROOT"
echo "Bundle root: $ACTUAL_BUNDLE_ROOT"

for rel in "${required_paths[@]}"; do
  src="$ACTUAL_BUNDLE_ROOT/$rel"
  dst="$REPO_ROOT/$rel"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN copy: $src -> $dst"
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo "Copied: $rel"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run complete. No files changed."
  exit 0
fi

if [[ "$SKIP_VALIDATE" -eq 1 ]]; then
  echo "Skipping deploy validation (--skip-validate)."
  exit 0
fi

echo "Running deploy validation..."
bash "$REPO_ROOT/scripts/validate_repo_safety.sh" --mode deploy

echo "Materialization complete. Use this working copy only for private execution, not for commit/push."
