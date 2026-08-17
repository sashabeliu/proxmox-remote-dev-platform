#!/usr/bin/env python3
"""Materialize runtime deployment files from one local site config.

The config file is intentionally local/private. The repo carries only
config/site.example.yml. This script writes the runtime files expected by OpenTofu/Ansible execution,
plus an optional shell env file for wrapper scripts.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any

try:
    import yaml  # type: ignore
except Exception as exc:  # pragma: no cover - exercised on minimal hosts
    raise SystemExit(
        "error: PyYAML is required to read site config. Install python3-yaml or ansible."
    ) from exc


SENSITIVE_KEY_RE = re.compile(r"(token|secret|password|auth[_-]?key|api_key)", re.I)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Materialize ignored runtime files from a local site.yml config."
    )
    parser.add_argument("--config", required=True, help="Path to local site.yml")
    parser.add_argument("--repo-root", default=Path(__file__).resolve().parents[1])
    parser.add_argument("--env-out", help="Optional shell env file for wrapper scripts")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-validate", action="store_true")
    return parser.parse_args()


def load_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise SystemExit(f"error: config file does not exist: {path}")
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit("error: site config must be a YAML mapping")
    return data


def require(data: dict[str, Any], dotted: str) -> Any:
    cur: Any = data
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            raise SystemExit(f"error: missing required config key: {dotted}")
        cur = cur[part]
    if cur is None or cur == "":
        raise SystemExit(f"error: empty required config key: {dotted}")
    if isinstance(cur, str) and "<REPLACE_ME" in cur:
        raise SystemExit(f"error: placeholder value still present: {dotted}")
    return cur


def opt(data: dict[str, Any], dotted: str, default: Any = None) -> Any:
    cur: Any = data
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return default if cur is None else cur


def expand_path(value: str) -> str:
    return str(Path(os.path.expandvars(os.path.expanduser(value))))


def derive_public_key(private_key: str) -> str:
    pub_path = Path(private_key + ".pub")
    if pub_path.exists():
        return pub_path.read_text(encoding="utf-8").strip()
    result = subprocess.run(
        ["ssh-keygen", "-y", "-f", private_key],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise SystemExit(
            f"error: could not derive SSH public key from {private_key}: {result.stderr.strip()}"
        )
    return result.stdout.strip()


def hcl_string(value: Any) -> str:
    return json.dumps(str(value))


def hcl_bool(value: Any) -> str:
    return "true" if bool(value) else "false"


def write_file(path: Path, content: str, dry_run: bool) -> None:
    if dry_run:
        print(f"DRY-RUN write: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")
    print(f"Wrote: {path.relative_to(Path.cwd()) if path.is_relative_to(Path.cwd()) else path}")


def validate_token_shape(token: str) -> None:
    if "!" not in token or "=" not in token or "@" not in token.split("!", 1)[0]:
        raise SystemExit(
            "error: proxmox.api_token must have shape USER@REALM!TOKENID=SECRET"
        )


def validate_config(data: dict[str, Any]) -> None:
    token = str(require(data, "proxmox.api_token"))
    validate_token_shape(token)

    tailscale_key = str(require(data, "lab_profile.tailscale_lxc.auth_key"))
    if not tailscale_key.startswith("tskey-auth-"):
        raise SystemExit("error: lab_profile.tailscale_lxc.auth_key must start with tskey-auth-")

    key_file = expand_path(str(require(data, "external_runner.ansible_key_file")))
    if not Path(key_file).exists():
        raise SystemExit(f"error: external_runner.ansible_key_file does not exist: {key_file}")


def render_tfvars(data: dict[str, Any], public_key: str) -> str:
    p = data["proxmox"]
    cv = data["control_vm"]
    lp = data["lab_profile"]
    dev = lp["dev_vm"]
    lxc = lp["tailscale_lxc"]
    gpu = lp.get("gpu_dev_vms", {}) or {}

    lines = [
        f"proxmox_endpoint = {hcl_string(p['api_endpoint_external'])}",
        f"proxmox_insecure = {hcl_bool(p.get('insecure', True))}",
        "",
        f"target_node    = {hcl_string(p['target_node'])}",
        f"template_vm_id = {int(p['template_vm_id'])}",
        f"bridge         = {hcl_string(p['bridge'])}",
        "",
        f"ci_user = {hcl_string(lp.get('ci_user', 'ubuntu'))}",
        "",
        f"ssh_public_key = {hcl_string(public_key)}",
        "",
        "control_vms = {",
        f"  {cv['name']} = {{",
        f"    vm_id     = {int(cv['vm_id'])}",
        f"    cpu_cores = {int(cv['cpu_cores'])}",
        f"    memory_mb = {int(cv['memory_mb'])}",
        f"    disk_gb   = {int(cv['disk_gb'])}",
        f"    ip_cidr   = {hcl_string(cv['ip_cidr'])}",
        f"    gateway   = {hcl_string(cv.get('gateway', p['gateway']))}",
        f"    cpu_type  = {hcl_string(cv.get('cpu_type', 'host'))}",
        "  }",
        "}",
        "",
        "dev_vms = {",
        f"  {dev['name']} = {{",
        f"    vm_id         = {int(dev['vm_id'])}",
        f"    cpu_cores     = {int(dev['cpu_cores'])}",
        f"    memory_mb     = {int(dev['memory_mb'])}",
        f"    disk_gb       = {int(dev['disk_gb'])}",
        f"    ip_cidr       = {hcl_string(dev['ip_cidr'])}",
        f"    gateway       = {hcl_string(dev.get('gateway', p['gateway']))}",
        f"    ansible_group = {hcl_string(dev.get('ansible_group', 'dev'))}",
        "  }",
        "}",
        "",
    ]

    if gpu:
        lines.append("gpu_dev_vms = {} # generated site config currently excludes GPU lab profile")
    else:
        lines.append("gpu_dev_vms = {}")
    lines.extend([
        "",
        "tailscale_lxcs = {",
        f"  {lxc['name']} = {{",
        f"    vm_id                  = {int(lxc['vm_id'])}",
        f"    cpu_cores              = {int(lxc['cpu_cores'])}",
        f"    memory_mb              = {int(lxc['memory_mb'])}",
        f"    swap_mb                = {int(lxc['swap_mb'])}",
        f"    disk_gb                = {int(lxc['disk_gb'])}",
        f"    ip_cidr                = {hcl_string(lxc['ip_cidr'])}",
        f"    gateway                = {hcl_string(lxc.get('gateway', p['gateway']))}",
        f"    datastore_id           = {hcl_string(lxc.get('datastore_id', 'local-lvm'))}",
        f"    template_file_id       = {hcl_string(lxc['template_file_id'])}",
        f"    ostype                 = {hcl_string(lxc.get('ostype', 'debian'))}",
        f"    unprivileged           = {hcl_bool(lxc.get('unprivileged', False))}",
        f"    enable_tun_passthrough = {hcl_bool(lxc.get('enable_tun_passthrough', False))}",
        "  }",
        "}",
        "",
    ])
    return "\n".join(lines)


def render_yaml(data: Any) -> str:
    return yaml.safe_dump(data, sort_keys=False, default_flow_style=False)


def project_vars(data: dict[str, Any], gpu: bool) -> list[dict[str, Any]]:
    out = []
    for project in opt(data, "dev_projects", []) or []:
        mode = project.get("gpu" if gpu else "cpu", {}) or {}
        item = {k: v for k, v in project.items() if k not in {"cpu", "gpu"}}
        item.update(mode)
        out.append(item)
    return out


def materialize(data: dict[str, Any], repo_root: Path, env_out: Path | None, dry_run: bool) -> None:
    validate_config(data)
    ansible_key = expand_path(str(require(data, "external_runner.ansible_key_file")))
    public_key = derive_public_key(ansible_key)

    p = data["proxmox"]
    lp = data["lab_profile"]
    lxc = lp["tailscale_lxc"]
    guest_ts = opt(data, "guest_tailscale", {}) or {}
    storage = opt(data, "shared_storage", {}) or {}
    code = opt(data, "code_server", {}) or {}

    files: dict[str, str] = {}
    files["tofu/proxmox.env"] = "\n".join(
        [
            f"export PROXMOX_VE_ENDPOINT={shlex.quote(str(p['api_endpoint_external']))}",
            f"export PROXMOX_VE_API_TOKEN={shlex.quote(str(p['api_token']))}",
            f"export PROXMOX_VE_INSECURE={shlex.quote(str(bool(p.get('insecure', True))).lower())}",
            "",
        ]
    )
    files["tofu/terraform.tfvars"] = render_tfvars(data, public_key)

    files["ansible/group_vars/all.yml"] = render_yaml(
        {
            "common_packages": opt(data, "common_packages", ["curl", "git", "htop", "tmux", "vim"]),
            "tailscale_auth_key": guest_ts.get("auth_key", ""),
            "tailscale_args": guest_ts.get("args", "--ssh"),
            "tailscale_exit_node": guest_ts.get("exit_node", ""),
            "tailscale_exit_node_allow_lan_access": bool(guest_ts.get("exit_node_allow_lan_access", False)),
            "tailscale_debug": bool(guest_ts.get("debug", False)),
        }
    )

    base_dev = {
        "docker_user": "ubuntu",
        "workspace_root": "/home/ubuntu/work",
        "shared_root": storage.get("mount_point", "/mnt/shared"),
        "storage_server_ip": storage.get("server_ip", "192.168.1.102"),
        "storage_export_path": storage.get("export_path", "/srv/shared"),
        "storage_mount_point": storage.get("mount_point", "/mnt/shared"),
        "storage_mount_opts": storage.get("mount_opts", "defaults,_netdev"),
        "code_server_bind_addr": code.get("bind_addr", "0.0.0.0:8080"),
        "code_server_auth": code.get("auth", "password"),
        "code_server_password": code.get("password", ""),
    }
    dev_vars = dict(base_dev)
    dev_vars["dev_projects"] = project_vars(data, gpu=False)
    gpu_vars = dict(base_dev)
    gpu_vars["dev_projects"] = project_vars(data, gpu=True)
    files["ansible/group_vars/dev.yml"] = render_yaml(dev_vars)
    files["ansible/group_vars/gpu_dev.yml"] = render_yaml(gpu_vars)

    files["ansible/group_vars/tailscale_lxc.yml"] = render_yaml(
        {
            "tailscale_lxc_auth_key": lxc["auth_key"],
            "tailscale_lxc_args": lxc.get("args", "--ssh"),
            "tailscale_lxc_advertise_routes": lxc.get("advertise_routes", ["192.168.2.0/24"]),
            "tailscale_lxc_advertise_exit_node": bool(lxc.get("advertise_exit_node", False)),
            "tailscale_lxc_accept_routes": bool(lxc.get("accept_routes", False)),
            "tailscale_lxc_remap_enabled": bool(lxc.get("remap_enabled", True)),
            "tailscale_lxc_real_subnet": lxc.get("real_subnet", "192.168.1.0/24"),
            "tailscale_lxc_tailnet_subnet": lxc.get("tailnet_subnet", "192.168.2.0/24"),
            "tailscale_lxc_lan_interface": lxc.get("lan_interface", "eth0"),
            "tailscale_lxc_debug": bool(lxc.get("debug", False)),
            "ansible_user": "root",
            "ansible_ssh_private_key_file": "/home/ubuntu/.ssh/ansible_ed25519",
            "ansible_python_interpreter": "/usr/bin/python3",
        }
    )

    template_file = lxc.get("template_file") or str(lxc["template_file_id"]).split("/")[-1]
    files["ansible/group_vars/proxmox_hosts.yml"] = render_yaml(
        {
            "tailscale_lxc_host_require_existing": False,
            "tailscale_lxc_host_containers": {
                lxc["name"]: {
                    "vm_id": int(lxc["vm_id"]),
                    "template_storage": p.get("lxc_template_storage", "local"),
                    "template_file": template_file,
                    "restart_on_raw_config_change": True,
                    "raw_config_lines": [
                        {"regexp": r"^features:.*$", "line": "features: keyctl=1,nesting=1"},
                        {"regexp": r"^lxc\.mount\.entry:\s+/dev/net/tun\b.*$", "line": "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file"},
                        {"regexp": r"^lxc\.apparmor\.profile:.*$", "line": "lxc.apparmor.profile: unconfined"},
                        {"regexp": r"^lxc\.cgroup2\.devices\.allow:.*$", "line": "lxc.cgroup2.devices.allow: a"},
                        {"regexp": r"^lxc\.cap\.drop:.*$", "line": "lxc.cap.drop: "},
                    ],
                }
            },
        }
    )

    for rel, content in files.items():
        write_file(repo_root / rel, content, dry_run)

    if env_out:
        env = {
            "SITE_NAME": opt(data, "site.name", ""),
            "SITE_ANSIBLE_KEY_FILE": ansible_key,
            "SITE_PROXMOX_HOST": p["pre_wipe_ssh_host"],
            "SITE_POST_WIPE_PROXMOX_HOST": p.get("post_wipe_ssh_host", p["pre_wipe_ssh_host"]),
            "SITE_CONTROL_PROXMOX_SSH_HOST": p.get("control_ssh_host", p["pre_wipe_ssh_host"]),
            "SITE_CONTROL_PROXMOX_API_ENDPOINT": p.get("api_endpoint_from_control_vm", p["api_endpoint_external"]),
            "SITE_CONTROL_VM_NAME": data["control_vm"]["name"],
            "SITE_CONTROL_VM_ID": str(data["control_vm"]["vm_id"]),
            "SITE_CONTROL_VM_IP_CIDR": data["control_vm"]["ip_cidr"],
            "SITE_CONTROL_VM_GATEWAY": data["control_vm"].get("gateway", p["gateway"]),
            "SITE_CONTROL_VM_CPU_TYPE": data["control_vm"].get("cpu_type", "host"),
            "SITE_TOFU_APPLY_TIMEOUT_SECONDS": str(lp.get("tofu_apply_timeout_seconds", 180)),
        }
        content = "".join(f"export {k}={shlex.quote(str(v))}\n" for k, v in env.items())
        write_file(env_out, content, dry_run)

    if not dry_run:
        for rel in ["tofu/proxmox.env"]:
            os.chmod(repo_root / rel, 0o600)
        if env_out and env_out.exists():
            os.chmod(env_out, 0o600)


def main() -> None:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    config = load_config(Path(args.config).expanduser().resolve())
    env_out = Path(args.env_out).resolve() if args.env_out else None
    materialize(config, repo_root, env_out, args.dry_run)
    if not args.dry_run and not args.skip_validate:
        subprocess.run(
            ["bash", str(repo_root / "scripts" / "validate_repo_safety.sh"), "--mode", "deploy"],
            check=True,
        )


if __name__ == "__main__":
    main()
