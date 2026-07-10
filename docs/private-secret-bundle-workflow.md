# Private Secret Bundle Workflow

## Purpose

This document defines the minimum safe workflow for storing and restoring the unsanitized execution files required by this platform.

The public repository keeps sanitized placeholders in their real relative paths.
The private bundle keeps the real values outside git.

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
scripts/validate_repo_safety.sh --mode repo
```

Windows:

```text
scripts\validate_repo_safety.cmd --mode repo
```

Expected result:
- passes only when tracked files remain sanitized

### Before running OpenTofu or Ansible
1. Start from a clean private working copy of the repo.
2. Copy the unsanitized files from the private bundle into the matching tracked paths.
3. Confirm you are operating in a private execution context, not a branch you intend to push.
4. Run deploy validation.

```bash
scripts/validate_repo_safety.sh --mode deploy
```

Windows:

```text
scripts\validate_repo_safety.cmd --mode deploy
```

Expected result:
- passes only when the execution-critical placeholders have been replaced locally

## Operational guidance

Preferred operator pattern:
- keep one public/safe working copy for documentation and git work
- keep one private execution working copy for running OpenTofu and Ansible with real values

This reduces the chance of accidentally committing secret substitutions.

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
