# Scripts

This directory contains helper scripts that support:
- inventory rendering
- validation
- preflight checks
- rebuild orchestration
- backup verification

## Current scripts

- `render_inventory.py`
  - renders Ansible inventory from OpenTofu outputs

- `provision_all.sh`
  - orchestrates the end-to-end provisioning flow

- `provision_and_configure.sh`
  - provisions and then configures guests

- `validate_repo_safety.sh`
  - validates that the repository is safe to commit/push or that a private working copy is ready to execute
  - modes:
    - `--mode repo` checks that sanitized tracked files still contain placeholders and that obvious secret/state artifacts are absent
    - `--mode deploy` checks that execution-critical placeholder files have been replaced in a private working copy before apply/playbook steps

- `validate_repo_safety.cmd`
  - Windows-friendly wrapper for the shell validator

- `install_git_hooks.sh`
  - configures `core.hooksPath` to use the repo-managed hooks in `.githooks/`

- `install_git_hooks.cmd`
  - Windows-friendly wrapper for hook installation via `git config core.hooksPath .githooks`

Only scripts that are safe to publish and maintain should be copied here.
