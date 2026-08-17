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

- `materialize_site_config.py`
  - preferred materializer for the current workflow
  - writes runtime execution files from one local private `site.yml`
  - supports `--config`, `--repo-root`, `--env-out`, `--dry-run`, and `--skip-validate`
  - runs deploy validation by default after materializing

- `rebuild_from_zero_lab.sh`
  - zero-to-lab orchestration entrypoint
  - preferred form uses `--config ~/.config/proxmox-remote-dev-platform/site.yml`
  - can bootstrap Proxmox, create VM101, hand off to VM101, and rebuild the non-GPU lab profile

- `rebuild_lab_profile.sh`
  - VM101-side lab-profile rebuild for `dev-00` plus `tailscale-rulab`
  - supports safe plan/check mode and `--apply --destroy-existing` for the selected non-GPU lab resources only

- `materialize_private_config.sh`
  - legacy compatibility helper that copies unsanitized execution files from a private bundle into a private working copy
  - supports `--bundle-root`, `--repo-root`, `--dry-run`, and `--skip-validate`
  - runs deploy validation by default after copying

- `materialize_private_config.cmd`
  - Windows-friendly wrapper for legacy private config materialization

Only scripts that are safe to publish and maintain should be copied here.
