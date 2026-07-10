#!/usr/bin/env python3
import json
import subprocess
from pathlib import Path

TOFU_DIR = Path("/home/ubuntu/infra/tofu")
ANSIBLE_INVENTORY = Path("/home/ubuntu/infra-ansible/inventory/hosts.ini")


def get_tofu_output() -> dict:
    result = subprocess.run(
        ["tofu", "output", "-json", "ansible_hosts"],
        cwd=TOFU_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
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
    lines.append("ansible_ssh_private_key_file=/home/ubuntu/.ssh/ansible_ed25519")
    lines.append("ansible_python_interpreter=/usr/bin/python3")
    lines.append("")

    return "\n".join(lines)


def refresh_known_hosts(hosts: dict) -> None:
    known_hosts = Path("/home/ubuntu/.ssh/known_hosts")
    known_hosts.parent.mkdir(parents=True, exist_ok=True)

    for _, meta in hosts.items():
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
