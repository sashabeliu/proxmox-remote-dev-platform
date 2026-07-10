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

Recommended action:
- convert recovery docs into exact commands and validation points
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
