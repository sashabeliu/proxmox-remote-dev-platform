# Guest Tailscale and Repository Prerequisites

## Purpose
During rebuild rehearsal, guest VM Tailscale connection and workload repository setup may be intentionally skipped so the infrastructure path can continue.

Skipping them is acceptable only as a scoped rehearsal shortcut. It must be recorded as deferred work, not counted as complete application recovery.

## Guest VM Tailscale prerequisites
Before running the guest Tailscale role end-to-end, provide a fresh key in the private execution copy.

Required:
- Tailscale auth key that is not expired, deleted, or already consumed
- key/OAuth policy allows the intended device behavior
- Tailnet ACL permits any requested tags
- Tailscale SSH is intentionally enabled if `tailscale_args` includes `--ssh`
- configured exit node exists and is reachable if `tailscale_exit_node` is set
- operator has Tailscale admin-console access to validate device presence and route/exit-node state

Private file:
- `ansible/group_vars/all.yml`

Required vars:
```yaml
tailscale_auth_key: "<fresh-auth-key>"
tailscale_args: "--ssh"
tailscale_exit_node: "<tailnet-exit-node-or-empty>"
tailscale_exit_node_allow_lan_access: true
tailscale_debug: false
```

OAuth usage:
- store OAuth client ID/secret only in the private bundle or secret manager
- use OAuth only to generate short-lived auth keys for the rebuild
- never commit OAuth credentials or generated auth keys

## Workload repository prerequisites
Before running GitHub deploy-key setup and repo clone/bootstrap end-to-end, provide valid GitHub access.

Required:
- GitHub token exported as `GITHUB_TOKEN` in the private execution shell
- token can read existing deploy keys for each configured repo
- token can create deploy keys for each configured repo
- target repos exist and are reachable
- generated guest SSH deploy key exists at `/home/<docker_user>/.ssh/git_ed25519`
- GitHub host key handling is compatible with the Ansible version in use
- upstream branch in each `dev_projects[].version` exists

Private/configured sources:
- environment variable: `GITHUB_TOKEN`
- `ansible/group_vars/dev.yml`
- `ansible/group_vars/gpu_dev.yml`

Relevant vars:
```yaml
dev_projects:
  - name: iris-poc
    repo_url: "git@github.com:iris-insight/iris-poc.git"
    version: "main"
    github_owner: "iris-insight"
    github_repo: "iris-poc"
```

## Known rehearsal evidence
On `proxmox-rulab`, the post-Tailscale guest configuration path for `dev-00` was proven after skipping the stale Tailscale join:
- Docker active
- NFS `/mnt/shared` mounted
- GitHub deploy-key registration succeeded with recovered GitHub credentials
- workload repo cloned
- project container build/start and smoke test succeeded
- code-server enabled

This proves guest provisioning and post-Tailscale Ansible convergence, but not a fresh Tailnet join.

## How to skip deliberately during a rehearsal
If credentials are not ready, do not repeatedly retry stale keys. Instead:
1. record that guest Tailscale join is deferred
2. record that workload repo setup is deferred, if GitHub credentials are also unavailable
3. continue only with independent infrastructure checks
4. do not mark final acceptance complete until fresh credentials are supplied and the full playbook succeeds from the beginning

Example narrow continuation after a Tailscale failure:
```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private/ansible
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/hosts.ini site.yml --limit dev-00 --start-at-task 'common : Update apt cache'
```

Use this only as rehearsal evidence for downstream roles, not as final recovery proof.
