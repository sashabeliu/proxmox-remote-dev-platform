# Lab Profile Rebuild: dev-00 + tailscale-rulab

## Purpose

This is the lab-safe rebuild profile for `proxmox-rulab`.

It intentionally includes:
- VM `110` `dev-00`
- CT `100` `tailscale-rulab`

It intentionally excludes:
- VM `121` `gpu-dev-01`

Reason: the lab host does not have the production GPU mapping and cannot safely satisfy the production `gpu-dev-01` CPU/GPU shape.

## What this proves

A successful lab-profile run proves that the core non-GPU platform can be recreated automatically after cleaning the selected lab VM/LXC:

1. Proxmox-host LXC preflight:
   - `/dev/net/tun` exists on the Proxmox host
   - Debian 12 LXC template exists on Proxmox storage
2. OpenTofu targeted apply:
   - creates `dev-00`
   - creates `tailscale-rulab`
   - excludes `gpu-dev-01` by using explicit targets
   - tolerates the known first-boot condition where a cloned VM exists but QEMU guest agent is not running yet
3. Proxmox-host LXC post-create role:
   - applies `features: keyctl=1,nesting=1`
   - applies raw `/dev/net/tun` LXC config
   - stops/starts CT `100` if needed
   - verifies `/dev/net/tun` inside the CT
4. Inventory render:
   - renders `dev` group
   - renders `tailscale_lxc` group
   - sets `tailscale_lxc` SSH user to `root`
5. Ansible configuration:
   - configures `tailscale-rulab`
   - configures base `dev-00` profile without GPU

## Script

Run from the private execution clone on VM `101`:

```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private
bash scripts/rebuild_lab_profile.sh
```

Default mode is safe plan/check mode:
- no destructive cleanup
- no OpenTofu apply
- no final Ansible convergence

To apply without cleaning existing guests:

```bash
bash scripts/rebuild_lab_profile.sh --apply
```

To prove clean rebuild of the selected lab profile:

```bash
bash scripts/rebuild_lab_profile.sh --apply --destroy-existing
```

This removes only:

```text
VM 110 dev-00
CT 100 tailscale-rulab
```

It does not target or destroy:

```text
VM 121 gpu-dev-01
```

## OpenTofu targets

The script uses explicit OpenTofu targets:

```text
proxmox_virtual_environment_vm.dev["dev-00"]
proxmox_virtual_environment_container.tailscale_lxc["tailscale-rulab"]
```

This is how `gpu-dev-01` is excluded even if it is still present in `terraform.tfvars`.

## Private lab overrides required

The lab script writes a private generated `tofu/lab-profile.auto.tfvars.json` with lab-safe values. Equivalent values are:

```hcl
dev_vms = {
  dev-00 = {
    vm_id         = 110
    cpu_cores     = 4
    memory_mb     = 8192
    disk_gb       = 80
    ip_cidr       = "192.168.1.112/24"
    gateway       = "192.168.1.1"
    ansible_group = "dev"
  }
}

tailscale_lxcs = {
  tailscale-rulab = {
    vm_id                  = 100
    cpu_cores              = 1
    memory_mb              = 1024
    swap_mb                = 1024
    disk_gb                = 8
    ip_cidr                = "192.168.1.212/24"
    gateway                = "192.168.1.1"
    datastore_id           = "local-lvm"
    template_file_id       = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
    ostype                 = "debian"
    unprivileged           = false
    enable_tun_passthrough = false
  }
}
```

Important: keep `enable_tun_passthrough = false` for API-token based OpenTofu applies. The root-only TUN and LXC feature settings are applied by the Proxmox-host Ansible role.

The private `ansible/group_vars/proxmox_hosts.yml` should map CT `100`:

```yaml
tailscale_lxc_host_containers:
  tailscale-rulab:
    vm_id: 100
    template_storage: local
    template_file: debian-12-standard_12.12-1_amd64.tar.zst
    restart_on_raw_config_change: true
    raw_config_lines:
      - regexp: '^features:.*$'
        line: 'features: keyctl=1,nesting=1'
      - regexp: '^lxc\.mount\.entry:\s+/dev/net/tun\b.*$'
        line: 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file'
      - regexp: '^lxc\.apparmor\.profile:.*$'
        line: 'lxc.apparmor.profile: unconfined'
      - regexp: '^lxc\.cgroup2\.devices\.allow:.*$'
        line: 'lxc.cgroup2.devices.allow: a'
      - regexp: '^lxc\.cap\.drop:.*$'
        line: 'lxc.cap.drop: '
```

The private `ansible/group_vars/tailscale_lxc.yml` must contain a fresh Tailscale auth key and route/remap settings.

## Dev Ansible scope

By default, the lab profile playbook uses:

```text
ansible/site-lab-profile.yml
```

For `dev-00`, this runs:
- `common`
- `docker`
- `storage_client`
- `git_ssh`
- `code_server`

The `common` role installs and starts `qemu-guest-agent` for VM guests. This matters because the Proxmox provider may wait for QEMU guest-agent data during VM create/refresh. In a clean rebuild from a template that does not already have the agent running, the script wraps targeted `tofu apply` with `TOFU_APPLY_TIMEOUT_SECONDS`, verifies VM `110` and CT `100` exist, enables the VM `110` QGA device, waits for SSH/cloud-init, installs/starts `qemu-guest-agent` if needed, imports missing resources into OpenTofu state, then runs Ansible and a post-Ansible OpenTofu drift check.

It intentionally skips guest-side roles that require fresh external credentials or app repository state:
- guest `tailscale`
- `github_deploy_key`
- `git_workspace`
- `project_bringup`

To run the full dev play anyway:

```bash
bash scripts/rebuild_lab_profile.sh --apply --full-dev
```

Only use `--full-dev` when fresh guest Tailscale, GitHub, and repository prerequisites are ready.

## Remaining external Tailscale step

After a clean recreate, Tailscale creates a new node identity. Previous route approval for the old node does not transfer automatically.

If ACL auto-approval is not configured, approve this route for the recreated node:

```text
192.168.2.0/24
```

Verify after approval:

```bash
ssh proxmox-rulab 'pct exec 100 -- tailscale status --json | jq ".Self | {DNSName,PrimaryRoutes,AllowedIPs}"'
```

Expected:

```text
PrimaryRoutes includes 192.168.2.0/24
AllowedIPs includes 192.168.2.0/24
```

## Acceptance

The lab profile is considered rebuilt when:
- VM `110 dev-00` exists and SSH works
- QEMU guest agent responds for VM `110`
- CT `100 tailscale-rulab` exists and SSH works
- `tailscaled` is active in CT `100`
- `/dev/net/tun` is visible in CT `100`
- forwarding is enabled in CT `100`
- `/etc/iptables/rules.v4` persists the NETMAP rules
- live NAT table contains the NETMAP/MASQUERADE rules
- Tailscale route `192.168.2.0/24` is approved or auto-approved
- `gpu-dev-01` remains excluded from this lab profile

## Latest verification

Verified on `2026-08-17` during a destructive zero-config rebuild from the public repo plus `~/.config/proxmox-remote-dev-platform/site.yml`:

- The lab host was wiped first: VM `101 ansible-control`, VM `110 dev-00`, VM/template `9000 ubuntu-22-template`, CT `100 tailscale-rulab`, and the local Debian 12 LXC template were removed.
- The rebuild recreated VM/template `9000`, VM `101 ansible-control`, VM `110 dev-00`, and CT `100 tailscale-rulab`.
- VM `101` and VM `110` were running and `qm agent 101 ping` / `qm agent 110 ping` both returned success.
- CT `100` was running with active `tailscaled`, visible `/dev/net/tun`, IPv4 and IPv6 forwarding enabled, and live NETMAP/MASQUERADE NAT rules.
- Tailscale status reported `BackendState=Running` for `tailscale-rulab`.
- `PrimaryRoutes` included `192.168.2.0/24`.
- `AllowedIPs` included `192.168.2.0/24`.
- From VM `101`, Ansible ping succeeded for both `dev` and `tailscale_lxc` groups.
- The lab-profile Ansible convergence completed with `dev-00: failed=0` and `tailscale-rulab: failed=0`.
- From VM `101`, targeted OpenTofu drift check for `dev-00` and `tailscale-rulab` returned `TOFU_PLAN_RC=0` / `No changes`.

Rehearsal recovery notes:
- Proxmox host apt initially failed because the host used unreachable `ftp.ru.debian.org`; switching `/etc/apt/sources.list` to `http://deb.debian.org/debian` fixed host bootstrap.
- Recreated static-IP guests changed SSH host keys; clear or isolate `known_hosts` entries for recreated lab IPs before SSH wait checks.
- Fresh cloud-image clones can be SSH-ready before QEMU guest agent is installed/running; the recovery path must tolerate installing/starting QGA after first SSH.
