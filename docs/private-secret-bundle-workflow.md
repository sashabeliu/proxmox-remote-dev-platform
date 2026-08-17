# Private Secret Bundle Workflow (Legacy Compatibility)

## Purpose

The preferred workflow is now documented in `docs/site-config.md`: one public repo clone plus one local private `~/.config/proxmox-remote-dev-platform/site.yml`.

This document remains for legacy compatibility with older private-bundle/private-clone runbooks. Use it only when you intentionally need the old bundle layout.

The public repository keeps sanitized placeholders in their real relative paths.
The legacy private bundle keeps real values outside git and mirrors those paths.

## Scope

The private bundle is the location for unsanitized versions of:
- `tofu/proxmox.env`
- `tofu/terraform.tfvars`
- `ansible/group_vars/all.yml`
- `ansible/group_vars/dev.yml`
- `ansible/group_vars/gpu_dev.yml`

It may also later include:
- deploy keys
- vault password files
- age private keys
- other environment-specific secrets required during rebuild

## Recommended directory layout

Recommended private root example:
- `C:\Users\Alexander\OneDrive\private-infra-secrets\proxmox-remote-dev-platform\`

Inside that root, mirror the repo-relative paths exactly:

```text
private-infra-secrets/
  proxmox-remote-dev-platform/
    tofu/
      proxmox.env
      terraform.tfvars
    ansible/
      group_vars/
        all.yml
        dev.yml
        gpu_dev.yml
```

## Core rule

- Git repo = tracked interfaces and sanitized placeholders
- Private bundle = real secret values
- Validator = guardrail before commit/push or deploy

Do not commit the private bundle.
Do not store the only copy on one machine.

## Minimum acceptable storage pattern

1. Keep the private bundle outside the git repo.
2. Encrypt it at rest.
3. Back it up to at least two places:
   - one primary synced/private location
   - one offline or separately controlled backup
4. Record recovery instructions in a password manager note or equivalent secure operator note.

## Restore/materialization workflow

### Before commit or push
From repo root:

```bash
bash scripts/validate_repo_safety.sh --mode repo
```

Windows:

```text
scripts\validate_repo_safety.cmd --mode repo
```

Expected result:
- passes only when tracked files remain sanitized

### Before running OpenTofu or Ansible
1. Start from a clean private working copy of the repo.
2. Materialize the unsanitized files from the private bundle into the matching tracked paths.
3. Confirm you are operating in a private execution context, not a branch you intend to push.
4. Run deploy validation.

Bash:

```bash
bash scripts/materialize_private_config.sh --bundle-root <private-bundle-root>
```

Windows:

```text
scripts\materialize_private_config.cmd --bundle-root <private-bundle-root>
```

Notes:
- the bundle root may be either the repo-specific secret directory itself or its parent directory
- the helper refuses to copy files that still contain `<REPLACE_ME>` placeholders
- deploy validation runs automatically after copying unless `--skip-validate` is used
- use `--dry-run` to preview the copy plan

```bash
bash scripts/validate_repo_safety.sh --mode deploy
```

Windows:

```text
scripts\validate_repo_safety.cmd --mode deploy
```

Expected result:
- passes only when the execution-critical placeholders have been replaced locally

## Operational guidance

Preferred current pattern:
- keep one public/safe repo clone as the source of truth
- keep one local private `site.yml` outside git
- let `scripts/rebuild_from_zero_lab.sh --config ...` or `scripts/materialize_site_config.py` generate runtime execution files when needed

Legacy/private-bundle pattern:
- keep one public/safe working copy for documentation and git work
- keep one private execution working copy for running OpenTofu and Ansible with real values

The legacy pattern reduces accidental commits, but it duplicates the repo and is no longer required for the tested non-GPU lab recovery.

## Recommended backup checklist

Back up:
- encrypted private bundle
- decryption key or password recovery path
- notes describing where each file is materialized
- any additional non-git secret dependencies

Do not rely on:
- memory alone
- one laptop
- one cloud sync folder as the only copy

## Option guidance

Best short-term option:
- encrypted private bundle outside git

Best longer-term upgrade:
- SOPS + age

Acceptable infra-native alternative:
- Ansible Vault

Not recommended as the first move here:
- HashiCorp Vault or another centralized secret manager, unless this platform becomes multi-operator or much more operationally critical
