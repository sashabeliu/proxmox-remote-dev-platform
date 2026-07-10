#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push scripts/validate_repo_safety.sh scripts/install_git_hooks.sh || true

echo "Configured git hooks for $(basename "$ROOT_DIR")"
echo "core.hooksPath=$(git config core.hooksPath)"
echo "Installed hooks:"
echo "- .githooks/pre-commit"
echo "- .githooks/pre-push"
