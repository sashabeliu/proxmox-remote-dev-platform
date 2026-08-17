# Current Risks

This file tracks the highest-value gaps between the current platform and the target state of fast, reliable rebuild from zero.

## Critical risks

### 1. No Proxmox scheduled backups observed
Impact:
- host or guest failure recovery depends too heavily on manual recreation and non-automated backup habits

Observed during audit:
- no cluster backup jobs were configured

Recommended action:
- define backup policy per VM/LXC
- configure scheduled Proxmox backups
- test at least one restore path

### 2. OpenTofu state currently stored locally on `ansible-control`
Impact:
- loss of the control VM can also mean loss of authoritative state metadata

Recommended action:
- define state handling explicitly
- at minimum back up the state file securely
- ideally move to a more deliberate state-management approach

### 3. Secrets are still placeholder-tracked here but live handling is not yet hardened
Impact:
- operators still need a disciplined manual process to inject secrets safely
- a careless edit could reintroduce live secrets into git

Recommended action:
- adopt stronger secret handling such as Ansible Vault, SOPS, or an external secret manager workflow
- add pre-commit or CI secret scanning

### 4. Shared storage and runtime data are not reproducible from code
Impact:
- infra can be recreated while workloads still remain unusable without data restore

Observed state:
- shared storage contains datasets, models, publishes, and user outputs

Recommended action:
- define exact backup targets and cadence for `/srv/shared`
- document restore order and ownership expectations

## Medium risks

### 5. Guest application repositories contain local drift
Impact:
- guest workloads may not be reproducible purely from upstream repos

Observed during audit:
- `iris-poc` had local modifications and untracked files on multiple guests

Recommended action:
- capture what is intentional machine-local state versus what should be committed upstream
- reduce hidden drift on long-lived VMs

### 6. Rebuild process still has undocumented manual assumptions
Impact:
- a future rebuild may stall on steps that currently exist only in operator memory

Observed/reduced during rehearsal:
- template and `ansible-control` command-level recovery paths are now documented and validated on `proxmox-rulab`
- one lab-only hardware fidelity gap remains: production uses `x86-64-v2-AES`, but the i3-2100 lab host can only run the fallback `x86-64-v2`
- OpenTofu init/validate/plan was proven on recreated VM 101; the full successful plan is unsafe to apply as-is on the lab host because it includes GPU VM `121` with 16 cores and `gpu-4070` PCI mapping, while `proxmox-rulab` has 4 CPUs and no PCI mappings
- targeted `dev-00` apply exposed and resolved several lab/private-config gaps: production `dev-00` requests 5 vCPUs, above the lab max of 4; the private `ssh_public_key` initially did not match the restored key; and production IP `192.168.1.110` collided/reached a different host during lab SSH verification
- clean targeted recreate of `dev-00` was proven with private-only lab overrides: VM `110`, 4 cores, 8192 MB RAM, 80G disk, `192.168.1.212/24`; OpenTofu apply completed, SSH from VM 101 succeeded, QEMU guest agent was installed/enabled and verified, inventory rendering produced the correct `dev-00` address, Ansible ping returned `pong`, Docker became active, GitHub deploy-key registration and `iris-poc` clone succeeded with the recovered original GitHub token, project container build/start and smoke tests succeeded, code-server was enabled, and NFS client storage mounted `/mnt/shared`
- true end-to-end guest Ansible convergence from the beginning is intentionally deferred at the Tailscale/repository boundary for now: the original control VM's Tailscale auth key was recovered/copied but is expired or deleted (`invalid key: API key does not exist`), and guest repository setup requires valid GitHub/deploy-key prerequisites; these are documented in `docs/guest-tailscale-and-repo-prerequisites.md`
- clean targeted recreate of the Tailscale LXC was proven on `proxmox-rulab`: CT `100 tailscale-rulab` was removed, recreated by OpenTofu, post-configured by the Proxmox-host Ansible role, configured inside the CT by the `tailscale_lxc` role, and verified with TUN, forwarding, persistent iptables, and live NETMAP rules
- because clean Tailscale LXC recreate creates a new Tailnet node identity, route approval for `192.168.2.0/24` can remain external unless Tailnet ACL `autoApprovers.routes` covers the rebuilt node; the current rebuilt lab node has the route approved and verified
- a lab-safe rebuild profile now exists in `scripts/rebuild_lab_profile.sh` and `docs/lab-profile-rebuild.md`; it targets `dev-00` plus `tailscale-rulab` and intentionally excludes `gpu-dev-01`
- combined clean non-GPU lab rebuild was performed: VM `110 dev-00` and CT `100 tailscale-rulab` were destroyed/recreated, host/LXC/dev Ansible convergence succeeded, QEMU guest agent was installed/started, and targeted OpenTofu post-Ansible plan returned no changes
- full destructive zero-config non-GPU lab rebuild was performed from a fresh public repo clone plus one local `~/.config/proxmox-remote-dev-platform/site.yml`: VM/template `9000`, VM `101`, VM `110`, CT `100`, and the Debian 12 LXC template were wiped and recreated; final acceptance passed with QGA on VM101/VM110, Ansible ping for `dev` and `tailscale_lxc`, Tailscale route `192.168.2.0/24` active, and targeted OpenTofu `No changes`
- the full zero-config rehearsal exposed three remaining automation hardening items: region-specific Debian apt mirrors can block host bootstrap, recreated static-IP guests need known_hosts cleanup/isolation, and QEMU guest-agent readiness should be treated as a post-SSH convergence step rather than a hard first-boot provider dependency

Recommended action:
- keep route approval/auto-approval as an explicit post-recreate check for every new Tailscale LXC identity
- use `scripts/rebuild_lab_profile.sh --apply --destroy-existing` for repeat clean non-GPU lab profile rebuilds; watch specifically for QEMU guest-agent availability during first boot and rely on the script's post-Ansible drift check
- keep guest Tailscale join and workload repository setup as explicit prerequisites unless running the lab script with `--full-dev`
- keep full GPU/prod-shaped apply deferred until the lab has matching capacity/mappings or a separate lab-safe GPU scope is defined
- continue converting recovery docs into exact commands and validation points
- record every manual step discovered during future rebuild rehearsals

### 7. Inventory generation mixes generated and static host knowledge
Impact:
- the boundary between provisioned assets and manually managed assets may be confusing during rebuild

Observed state:
- generated inventory incorporates static `storage-vm` information outside OpenTofu-managed outputs

Recommended action:
- document this boundary explicitly
- decide whether `storage-vm` remains manual or becomes provisioned

## Lower but important risks

### 8. Line-ending and cross-platform execution assumptions
Impact:
- scripts edited on Windows may behave differently on Linux control VMs if not normalized

Recommended action:
- enforce line-ending strategy with `.gitattributes`
- validate shell scripts on the execution host

### 9. Recovery repo is ahead of runbook maturity
Impact:
- the repo exists and is useful, but still needs a tested operator procedure to become trustworthy

Recommended action:
- perform a partial rebuild rehearsal
- document what failed or needed improvisation

## Exit criteria for calling this platform rebuild-ready

Minimum acceptable standard:
- scheduled backups configured
- state strategy documented and backed up
- secrets workflow hardened
- shared data restore process documented
- rebuild checklist validated in practice
