# Site Config

## Purpose

The preferred workflow is now:

```text
public repo clone
+ one local private site config
+ generated runtime files
```

This replaces the older `proxmox-remote-dev-platform-private` clone workflow.

## Files

Template in the repo:

```text
config/site.example.yml
```

Real local config on WSL/external runner:

```text
~/.config/proxmox-remote-dev-platform/site.yml
```

The real config is sensitive and must not be committed. It contains values such as:

```text
Proxmox API token
Tailscale auth key
code-server password
VM/CT IPs and IDs
control VM settings
```

## Create local config

```bash
cd /home/alexander/proxmox-remote-dev-platform
mkdir -p ~/.config/proxmox-remote-dev-platform
cp config/site.example.yml ~/.config/proxmox-remote-dev-platform/site.yml
chmod 600 ~/.config/proxmox-remote-dev-platform/site.yml
nano ~/.config/proxmox-remote-dev-platform/site.yml
```

Verify required private values:

```bash
test -f ~/.ssh/ansible_ed25519 && echo "SSH key present"
grep -q 'api_token:' ~/.config/proxmox-remote-dev-platform/site.yml && echo "Proxmox token field present"
grep -q 'tskey-auth-' ~/.config/proxmox-remote-dev-platform/site.yml && echo "Tailscale auth key present"
```

Use a reusable/preauthorized Tailscale auth key if repeated destructive CT100 rebuilds should work without generating a new key.

## Materialize runtime files manually

Usually `scripts/rebuild_from_zero_lab.sh --config ...` does this automatically. To materialize only:

```bash
python3 scripts/materialize_site_config.py \
  --config ~/.config/proxmox-remote-dev-platform/site.yml \
  --repo-root "$PWD"
```

This writes the runtime execution files that older runbooks used to get from a separate private clone:

```text
tofu/proxmox.env
tofu/terraform.tfvars
ansible/group_vars/all.yml
ansible/group_vars/dev.yml
ansible/group_vars/gpu_dev.yml
ansible/group_vars/tailscale_lxc.yml
ansible/group_vars/proxmox_hosts.yml
```

These files are execution material after materialization. Do not commit them with real secrets. The repo pre-commit/pre-push safety checks are expected to block high-confidence secrets.

## Full zero-to-lab command

```bash
cd /home/alexander/proxmox-remote-dev-platform

bash scripts/rebuild_from_zero_lab.sh \
  --config ~/.config/proxmox-remote-dev-platform/site.yml \
  --apply \
  --wipe-existing-guests-and-templates \
  --manage-apt-repos \
  --create-template \
  --create-control-vm \
  --handoff-to-control \
  --with-provider-mirror
```

## Lab-profile-only destructive rerun

From VM101, use the generated private execution directory created by the handoff. The path currently keeps the historical `-private` suffix for compatibility, but it is not a separately maintained duplicate repo:

```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private
TOFU_APPLY_TIMEOUT_SECONDS=180 \
LAB_PROXMOX_SSH_HOST=proxmox-rulab \
bash scripts/rebuild_lab_profile.sh --apply --destroy-existing
```

## Notes

- `--config` and `--private-bundle-root` are mutually exclusive.
- CLI flags still override config defaults when provided.
- `config/site.yml` and `config/*.local.yml` are ignored to reduce accidental commits if someone copies the real config into the repo.
- The local real config should be backed up in a private password manager or encrypted secret store.
