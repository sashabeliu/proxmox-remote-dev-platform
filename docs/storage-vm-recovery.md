# storage-vm Recovery

## Purpose
Recover the manually managed shared-storage VM and restore the NFS-backed data layer used by guest workloads.

## Current known target
Observed during audit:
- VM ID: `102`
- name: `storage-vm`
- IP: `192.168.1.102`
- exported path: `/srv/shared`
- guest mount point: `/mnt/shared`

Tracked storage vars:
- `ansible/group_vars/storage.yml`
  - `nfs_export_path: "/srv/shared"`
  - `nfs_export_network: "192.168.1.0/24"`
  - `nfs_export_opts: "rw,sync,no_subtree_check,no_root_squash"`
- `ansible/group_vars/dev.yml`
- `ansible/group_vars/gpu_dev.yml`

Repo roles involved:
- server: `ansible/roles/storage_server`
- clients: `ansible/roles/storage_client`

## Important current limitation
`storage-vm` is currently a static/manual host in inventory, not an OpenTofu-managed VM.
Its data is not reproducible from git and must come from backup.

## Recovery steps
1. Recreate or restore `storage-vm`.
2. Ensure it is reachable at the intended IP, or update inventory and group vars if you intentionally change it.
3. Restore the `/srv/shared` backup onto the VM.
4. Run the storage server configuration through Ansible.
5. Run guest configuration so dev and GPU guests remount the share.

## What the repo configures
### storage_server role
The server role does all of the following:
- installs `nfs-kernel-server`
- ensures `{{ nfs_export_path }}` exists
- writes the export line to `/etc/exports`
- runs `exportfs -ra`
- enables and starts `nfs-kernel-server`

### storage_client role
The client role does all of the following:
- installs `nfs-common`
- ensures the mount point exists
- mounts `{{ storage_server_ip }}:{{ storage_export_path }}` at `{{ storage_mount_point }}`

## Recovery commands
From the configured control environment:
```bash
cd ansible
ansible-playbook -i inventory/hosts.ini site.yml
```

This runs:
- storage server setup on `[storage]`
- storage client setup on `[dev]` and `[gpu_dev]`

## Validation
The storage recovery is acceptable only when all are true:
- `storage-vm` is reachable over SSH
- `/srv/shared` exists on the server and contains restored data
- NFS server is running
- dev and GPU guests can mount `/mnt/shared`
- required datasets/models/outputs are visible from clients

## Manual checks
Useful checks after recovery:
- confirm `/etc/exports` contains the intended line
- confirm `exportfs -v` shows `/srv/shared`
- confirm guests show `/mnt/shared` as mounted
- confirm a test file written on the server is visible on a client

## Known gaps
- this repo does not yet provision `storage-vm` itself
- the exact backup and restore cadence for `/srv/shared` is still a documented risk
- if `storage-vm` is rebuilt with a different IP or OS shape, inventory and vars must be updated deliberately
