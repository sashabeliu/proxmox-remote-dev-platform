# Topology

## Logical topology

```text
Operator workstation
  -> SSH / Tailscale
Proxmox host
  -> ansible-control VM
  -> storage-vm
  -> dev-00
  -> dev-01
  -> gpu-dev-01
  -> optional stopped templates / spare VMs
  -> mltailscale LXC
```

## Roles

- `ansible-control`: provisioning coordination and configuration entry point
- `storage-vm`: NFS shared storage server
- `dev-00`, `dev-01`: CPU-based development VMs
- `gpu-dev-01`: GPU-enabled development VM
- `mltailscale`: Tailscale utility LXC/subnet router; observed route advertisement is `192.168.2.0/24`
- `ubuntu-22-template`: template base used for cloning guests

## Network assumptions

Current observed LAN:
- Proxmox host bridge on `192.168.1.0/24`
- Proxmox host observed at `192.168.1.200`
- guest addressing currently appears statically assigned for core VMs
- `mltailscale` is expected at `192.168.1.100/24` when restored with production-shaped private values

Current observed Tailscale routing:
- `mltailscale` advertises `192.168.2.0/24`
- route approval remains a Tailnet-admin prerequisite unless the ACL policy auto-approves it

## Shared storage flow

`storage-vm` exports `/srv/shared` over NFS.
Guest VMs mount the share, currently observed at `/mnt/shared`.

## Operational flow

1. operator reaches Proxmox or control VM
2. control VM runs OpenTofu and Ansible
3. guests are provisioned and configured
4. users work inside guest VMs
5. large data and outputs live on shared storage or dedicated backups
