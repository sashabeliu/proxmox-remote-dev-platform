#!/usr/bin/env python3
import json
import os
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
TOFU_DIR = Path(os.environ.get("TOFU_DIR", REPO_ROOT / "tofu"))
ANSIBLE_INVENTORY = Path(
    os.environ.get("ANSIBLE_INVENTORY", REPO_ROOT / "ansible" / "inventory" / "hosts.ini")
)
ANSIBLE_SSH_KEY_FILE = os.environ.get(
    "ANSIBLE_SSH_KEY_FILE", "/home/ubuntu/.ssh/ansible_ed25519"
)
KNOWN_HOSTS_FILE = Path(
    os.environ.get("KNOWN_HOSTS_FILE", str(Path.home() / ".ssh" / "known_hosts"))
)


def get_tofu_output() -> dict:
    result = subprocess.run(
        ["tofu", "output", "-json", "ansible_hosts"],
        cwd=TOFU_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def get_optional_tofu_output(name: str) -> dict:
    result = subprocess.run(
        ["tofu", "output", "-json", name],
        cwd=TOFU_DIR,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return {}
    return json.loads(result.stdout)


def render_ini(hosts: dict) -> str:
    grouped: dict[str, list[tuple[str, str]]] = {}

    for name, meta in hosts.items():
        group = meta["group"]
        ip = meta["ip"]
        grouped.setdefault(group, []).append((name, ip))

    lines: list[str] = []

    for group in sorted(grouped.keys()):
        lines.append(f"[{group}]")
        for name, ip in sorted(grouped[group]):
            lines.append(f"{name} ansible_host={ip}")
        lines.append("")

    # static infrastructure not currently provisioned by Tofu
    lines.append("[storage]")
    lines.append("storage-vm ansible_host=192.168.1.102")
    lines.append("")

    lines.append("[all:vars]")
    lines.append("ansible_user=ubuntu")
    lines.append(f"ansible_ssh_private_key_file={ANSIBLE_SSH_KEY_FILE}")
    lines.append("ansible_python_interpreter=/usr/bin/python3")
    lines.append("")

    if "tailscale_lxc" in grouped:
        lines.append("[tailscale_lxc:vars]")
        lines.append("ansible_user=root")
        lines.append(f"ansible_ssh_private_key_file={ANSIBLE_SSH_KEY_FILE}")
        lines.append("ansible_python_interpreter=/usr/bin/python3")
        lines.append("")

    return "\n".join(lines)


def refresh_known_hosts(hosts: dict) -> None:
    known_hosts = KNOWN_HOSTS_FILE
    known_hosts.parent.mkdir(parents=True, exist_ok=True)

    for _, meta in hosts.items():
        if meta.get("group") == "tailscale_lxc":
            continue

        ip = meta["ip"]

        subprocess.run(
            ["ssh-keygen", "-f", str(known_hosts), "-R", ip],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

        scan = subprocess.run(
            ["ssh-keyscan", "-H", ip],
            capture_output=True,
            text=True,
            check=False,
        )

        if scan.stdout:
            with known_hosts.open("a") as f:
                f.write(scan.stdout)


def main() -> None:
    hosts = get_tofu_output()
    hosts.update(get_optional_tofu_output("tailscale_lxc_hosts"))

    if ANSIBLE_INVENTORY.exists():
        backup = ANSIBLE_INVENTORY.with_suffix(".ini.bak")
        backup.write_text(ANSIBLE_INVENTORY.read_text())

    content = render_ini(hosts)
    ANSIBLE_INVENTORY.write_text(content)
    refresh_known_hosts(hosts)

    groups = {}
    for name, meta in hosts.items():
        groups.setdefault(meta["group"], []).append(name)

    print(f"Wrote inventory to {ANSIBLE_INVENTORY}")
    for group, names in sorted(groups.items()):
        print(f"  {group}: {', '.join(sorted(names))}")
    print("  storage: storage-vm")


if __name__ == "__main__":
    main()
