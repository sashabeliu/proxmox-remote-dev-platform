# Tailscale Recovery

## Purpose
Recover Tailscale access for the platform without treating stale copied keys as rebuild proof.

There are now two separate scopes:
1. guest VM Tailscale join for `dev` and `gpu_dev`
2. automatic deployment of the Tailscale utility LXC `mltailscale`

## Current managed scope

### Guest VMs
The tracked `ansible/roles/tailscale` role applies to:
- `dev`
- `gpu_dev`

Guest VM Tailscale is intentionally skippable during infrastructure rehearsal when the required Tailnet credentials are not available or are stale. The rest of guest convergence can still be validated by starting after the Tailscale task, but that is not full end-to-end Tailscale recovery proof.

### Tailscale utility LXC
The repo now codifies automatic deployment of the observed Tailscale utility LXC:
- VMID: `100`
- hostname: `mltailscale`
- OS: Debian 12 LXC
- role: Tailscale subnet-router / utility container
- observed advertised route on the original server: `192.168.2.0/24`
- observed LAN remap on the original server: Tailnet-visible `192.168.2.0/24` maps to real LAN `192.168.1.0/24`

Automation layers:
- OpenTofu resource: `proxmox_virtual_environment_container.tailscale_lxc`
- variable: `tailscale_lxcs`
- Proxmox host playbook: `ansible/site-tailscale-lxc-host.yml`
- Proxmox host role: `ansible/roles/proxmox_tailscale_lxc_host`
- Ansible group: `tailscale_lxc`
- Ansible role: `ansible/roles/tailscale_lxc`
- Proxmox host vars: `ansible/group_vars/proxmox_hosts.yml`
- private vars: `ansible/group_vars/tailscale_lxc.yml`

## Required prerequisites

### For guest VM Tailscale join
You need a fresh Tailscale auth key in the private execution copy:
- key must not be expired, deleted, or already consumed if single-use
- key must allow the intended device settings
- if using tags, the Tailnet ACL must permit the key/OAuth client to assign those tags
- if using `--ssh`, Tailscale SSH must be intended and allowed by policy
- if using an exit node, `tailscale_exit_node` must point to a valid reachable Tailnet node

Private vars:
- `ansible/group_vars/all.yml`
  - `tailscale_auth_key`
  - `tailscale_args`
  - `tailscale_exit_node`
  - `tailscale_exit_node_allow_lan_access`
  - `tailscale_debug`

### For Tailscale LXC automatic deployment
You need all of these before applying the LXC scope:
- Proxmox API credentials with permission to create/start LXC containers
- root SSH access from the control VM to the target Proxmox host for host-side LXC compatibility automation
- the selected LXC template present on the target Proxmox storage, for example:
  - `local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst`
- free VMID/IP for `mltailscale` or a deliberate private override
- `/dev/net/tun` available on the Proxmox host
- LXC config that permits TUN access
- a fresh Tailscale auth key for the LXC
- Tailnet ACL/OAuth setup that permits route advertisement and any requested tags
- after first join, the advertised route must be approved in the Tailscale admin console unless policy auto-approves it
- persistent IPv4 NAT/NETMAP rules when the Tailnet-visible subnet differs from the real LAN subnet

The original server's LXC `100` had these Proxmox settings:
```text
features: nesting=1,keyctl=1
hostname: mltailscale
ip: 192.168.1.100/24
rootfs: local-lvm, 8G
unprivileged: 0
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
```

The OpenTofu provider models the common LXC shape. In the lab rebuild proof, the Proxmox API token could create CT `100`, but Proxmox rejected root-only privileged LXC mutations:

```text
configuring device passthrough is only allowed for root@pam
changing feature flags for privileged container is only allowed for root@pam
```

Therefore the supported automation split is:
- OpenTofu creates the basic privileged CT without provider-managed feature flags or `device_passthrough`.
- `ansible/site-tailscale-lxc-host.yml`, running as `root` over SSH to the Proxmox host, applies `features: keyctl=1,nesting=1` and raw `/dev/net/tun` LXC config after creation.
- `enable_tun_passthrough` should stay `false` for API-token based applies unless using `root@pam` credentials deliberately.

## Private configuration examples

Keep the public repo placeholders sanitized. In the private execution copy, set the LXC values in `tofu/terraform.tfvars`:

```hcl
tailscale_lxcs = {
  mltailscale = {
    vm_id            = 100
    cpu_cores        = 1
    memory_mb        = 1024
    swap_mb          = 1024
    disk_gb          = 8
    ip_cidr          = "192.168.1.100/24"
    gateway          = "192.168.1.1"
    datastore_id     = "local-lvm"
    template_file_id = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
    ostype                 = "debian"
    unprivileged           = false
    # Keep false when using an API token. Root-only TUN/feature config is applied by ansible/site-tailscale-lxc-host.yml.
    enable_tun_passthrough = false
  }
}
```

Set private LXC Tailscale values in `ansible/group_vars/tailscale_lxc.yml`:

```yaml
tailscale_lxc_auth_key: "<fresh-auth-key>"
tailscale_lxc_args: "--ssh"
tailscale_lxc_advertise_routes:
  - "192.168.2.0/24"
tailscale_lxc_advertise_exit_node: false
tailscale_lxc_accept_routes: false
tailscale_lxc_remap_enabled: true
tailscale_lxc_real_subnet: "192.168.1.0/24"
tailscale_lxc_tailnet_subnet: "192.168.2.0/24"
tailscale_lxc_lan_interface: "eth0"
```

If you generate the auth key with a Tailscale OAuth client, the OAuth client must have at least the `auth_keys` scope and be authorized for the requested tags/routes. Do not paste OAuth secrets or auth keys into logs or chat.

## Subnet remapping

The original LAN is `192.168.1.0/24`, but that subnet can conflict with other networks reached by Tailnet clients. The Tailscale LXC therefore advertises `192.168.2.0/24` and remaps it to the real LAN:

```text
Tailnet client accesses: 192.168.2.x
LXC translates to real LAN: 192.168.1.x
```

The original `mltailscale` used persistent iptables rules in `/etc/iptables/rules.v4`:

```text
-A PREROUTING -d 192.168.2.0/24 -j NETMAP --to 192.168.1.0/24
-A POSTROUTING -o eth0 -j MASQUERADE
-A POSTROUTING -d 192.168.1.0/24 -j NETMAP --to 192.168.2.0/24
```

The automated Ansible role now installs `iptables-persistent` / `netfilter-persistent`, writes `/etc/iptables/rules.v4`, enables `netfilter-persistent`, and applies the same rules live without flushing Tailscale's dynamic chains.

Manual verification:

```bash
pct exec 100 -- iptables-save -t nat | grep -E '192\.168\.1|192\.168\.2|NETMAP|MASQUERADE'
pct exec 100 -- ls -l /etc/iptables/rules.v4 /etc/iptables/rules.v6
```

## Recovery steps for Tailscale LXC

From the private control VM clone:

```bash
cd /home/ubuntu/proxmox-remote-dev-platform-private/tofu
set -a
. ./proxmox.env
set +a

tofu init

# Preflight host-side prerequisites before creating the LXC:
# - /dev/net/tun exists on the Proxmox host
# - Debian LXC template exists in Proxmox template storage
cd ../ansible
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
  -i inventory/proxmox-hosts.ini \
  site-tailscale-lxc-host.yml

cd ../tofu
tofu plan -target='proxmox_virtual_environment_container.tailscale_lxc["mltailscale"]'
tofu apply -target='proxmox_virtual_environment_container.tailscale_lxc["mltailscale"]'

# Post-create host-side compatibility step:
# - ensures features and raw /dev/net/tun LXC config lines exist in /etc/pve/lxc/100.conf
# - stops/starts the CT if those lines changed
cd ../ansible
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
  -i inventory/proxmox-hosts.ini \
  site-tailscale-lxc-host.yml

python ../scripts/render_inventory.py
ANSIBLE_HOST_KEY_CHECKING=False ansible -i inventory/hosts.ini tailscale_lxc -m ping
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/hosts.ini site.yml --limit tailscale_lxc
```

For a lab rebuild where the LXC is named `tailscale-rulab` and uses IP `192.168.1.213/24`, override both private maps consistently:

```yaml
# ansible/group_vars/proxmox_hosts.yml
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

## Validation

Clean LXC rebuild proof performed on `proxmox-rulab`:
- manually removed the previously unmanaged lab CT `100`
- recreated CT `100 tailscale-rulab` through targeted OpenTofu apply
- ran `ansible/site-tailscale-lxc-host.yml` to apply root-only Proxmox LXC config
- rendered inventory with `[tailscale_lxc:vars] ansible_user=root`
- ran `ansible/site.yml --limit tailscale_lxc`
- verified CT running, TUN visible, Tailscale installed, `tailscaled` active, forwarding enabled, persistent NETMAP rules installed, and live NETMAP/MASQUERADE rules present

Important: after a clean recreate, Tailscale creates a new node identity. Approval of the previous `tailscale-rulab` node's route does not transfer automatically. Unless ACL `autoApprovers.routes` covers this device/user/tag, approve `192.168.2.0/24` for the recreated node in Tailscale admin.

Observed before route approval on the recreated node:

```text
DNSName=tailscale-rulab-1.tail20bec0.ts.net.
AdvertiseRoutes includes 192.168.2.0/24
PrimaryRoutes=None
AllowedIPs only node IPs
```

The Tailscale LXC recovery is acceptable only when all are true:
- LXC `100` exists and starts on boot
- SSH/Ansible can reach `mltailscale`
- `tailscaled` is active inside the LXC
- `tailscale status --json` reports `BackendState=Running`
- `tailscale ip` returns Tailnet addresses
- expected subnet route, currently `192.168.2.0/24`, appears in the Tailnet admin console
- the advertised route is approved/enabled if policy does not auto-approve it
- `/etc/iptables/rules.v4` persists the `192.168.2.0/24` <-> `192.168.1.0/24` NETMAP remap rules
- `iptables-save -t nat` shows the live NETMAP/MASQUERADE rules
- an operator can reach the routed subnet through Tailscale

Useful checks:
```bash
pct config 100
pct status 100
pct exec 100 -- systemctl is-active tailscaled
pct exec 100 -- tailscale status
pct exec 100 -- tailscale ip
pct exec 100 -- sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
pct exec 100 -- iptables-save -t nat | grep -E '192\.168\.1|192\.168\.2|NETMAP|MASQUERADE'
```

## Rehearsal finding

During the `proxmox-rulab` rehearsal, the original control VM's copied Tailscale auth key was not valid anymore:

```text
invalid key: API key does not exist
```

This means copied long-lived auth keys are not a reliable recovery artifact. Document the OAuth client or key-generation procedure, but use a freshly generated auth key during rebuild validation.

During the later `tailscale-rulab` LXC rehearsal:
- CT `100` was created on `proxmox-rulab` as `tailscale-rulab`
- lab IP was set to `192.168.1.213/24` to avoid colliding with the original `192.168.1.100`
- `/dev/net/tun` was exposed into the LXC using the same raw LXC settings as the original container
- Tailscale `1.102.2` was installed from `pkgs.tailscale.com`
- `tailscaled` was enabled and running
- forwarding was enabled and persisted in `/etc/sysctl.d/99-tailscale-lxc.conf`
- direct Tailscale auth-key join succeeded after OAuth-generated key attempts were blocked by tag permissions
- persistent IPv4 NETMAP remap was installed in `/etc/iptables/rules.v4`

The live remap rules applied on `tailscale-rulab` were:

```text
-A PREROUTING -d 192.168.2.0/24 -j NETMAP --to 192.168.1.0/24
-A POSTROUTING -o eth0 -j MASQUERADE
-A POSTROUTING -d 192.168.1.0/24 -j NETMAP --to 192.168.2.0/24
```

At the time of writing, the node was connected to Tailscale but route activation still depended on the Tailnet admin route approval / auto-approval state.

## Known gaps
- fresh Tailscale auth-key generation is documented but not yet fully automated in repo scripts
- route approval in the Tailscale admin console remains an external/manual validation step unless ACL policy auto-approves it
- exact raw LXC compatibility settings may still vary by Proxmox version/provider support and should be validated on the target host
