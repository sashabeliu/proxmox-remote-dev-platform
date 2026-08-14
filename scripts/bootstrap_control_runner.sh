#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/bootstrap_control_runner.sh [--with-opentofu-provider-mirror]

Prepare the current Debian/Ubuntu control runner with the tools needed to bootstrap Proxmox and run the lab rebuild.
Run this on a temporary control VM, laptop WSL, or ansible-control clone before running rebuild_from_zero_lab.sh.

Options:
  --with-opentofu-provider-mirror  Also install bpg/proxmox provider v0.100.0 into ~/.terraform.d filesystem mirror.
  -h, --help                       Show this help.
EOF
}

WITH_PROVIDER_MIRROR=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-opentofu-provider-mirror) WITH_PROVIDER_MIRROR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "error: this bootstrap script currently supports Debian/Ubuntu runners with apt-get" >&2
  exit 1
fi

echo "== Install runner packages =="
export DEBIAN_FRONTEND=noninteractive
"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y \
  git \
  python3 \
  python3-pip \
  python3-venv \
  ansible \
  curl \
  ca-certificates \
  unzip \
  jq \
  gnupg \
  openssh-client

if ! command -v tofu >/dev/null 2>&1; then
  echo "== Install OpenTofu =="
  VERSION="${OPENTOFU_VERSION:-}"
  if [[ -z "$VERSION" ]]; then
    VERSION="$(curl -fsSL https://api.github.com/repos/opentofu/opentofu/releases/latest | jq -r .tag_name | sed 's/^v//')"
  fi
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fL "https://github.com/opentofu/opentofu/releases/download/v${VERSION}/tofu_${VERSION}_linux_amd64.zip" -o "$TMP/tofu.zip"
  unzip -q "$TMP/tofu.zip" -d "$TMP"
  "${SUDO[@]}" install -m 0755 "$TMP/tofu" /usr/local/bin/tofu
fi

if [[ "$WITH_PROVIDER_MIRROR" -eq 1 ]]; then
  echo "== Install OpenTofu provider mirror for bpg/proxmox =="
  PROVIDER_VERSION="${PROXMOX_PROVIDER_VERSION:-0.100.0}"
  OS_ARCH="linux_amd64"
  MIRROR_DIR="$HOME/.terraform.d/plugins/registry.opentofu.org/bpg/proxmox/${PROVIDER_VERSION}/${OS_ARCH}"
  mkdir -p "$MIRROR_DIR"
  if [[ ! -x "$MIRROR_DIR/terraform-provider-proxmox_v${PROVIDER_VERSION}" ]]; then
    TMP="$(mktemp -d)"
    curl -fL "https://github.com/bpg/terraform-provider-proxmox/releases/download/v${PROVIDER_VERSION}/terraform-provider-proxmox_${PROVIDER_VERSION}_${OS_ARCH}.zip" -o "$TMP/provider.zip"
    unzip -q "$TMP/provider.zip" -d "$TMP/provider"
    install -m 0755 "$TMP/provider/terraform-provider-proxmox_v${PROVIDER_VERSION}" "$MIRROR_DIR/terraform-provider-proxmox_v${PROVIDER_VERSION}"
    rm -rf "$TMP"
  fi
  cat >"$HOME/.terraformrc" <<EOF
provider_installation {
  filesystem_mirror {
    path    = "$HOME/.terraform.d/plugins"
    include = ["registry.opentofu.org/bpg/proxmox"]
  }
  direct {
    exclude = ["registry.opentofu.org/bpg/proxmox"]
  }
}
EOF
  cp "$HOME/.terraformrc" "$HOME/.tofurc"
fi

echo "== Versions =="
git --version
python3 --version
ansible-playbook --version | sed -n '1,3p'
tofu version

echo "Control runner bootstrap complete."
