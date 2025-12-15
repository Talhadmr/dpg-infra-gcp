#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Terraform output.json -> Kubespray inventory.ini generator

Input example (your format):
{
  "master-01": {"ip": "10.10.10.2", "role": "control"},
  "worker-01": {"ip": "10.10.10.5", "role": "worker"}
}

Output (INI-like) groups:
[all]
[kube_control_plane]
[etcd]
[kube_node]
[calico_rr]
[k8s_cluster:children]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Dict, List, Tuple


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Generate Kubespray inventory.ini from Terraform output.json"
    )
    p.add_argument(
        "-i",
        "--input",
        default="output.json",
        help="Path to terraform output json (default: output.json)",
    )
    p.add_argument(
        "-o",
        "--output",
        default="inventory.ini",
        help="Path to write inventory.ini (default: inventory.ini)",
    )
    p.add_argument(
        "--ansible-user",
        default="",
        help="Optional: ansible_user to embed into host lines (e.g. debian, ubuntu). Default: empty",
    )
    p.add_argument(
        "--ansible-port",
        default="22",
        help="Optional: SSH port (default: 22)",
    )
    p.add_argument(
        "--become",
        action="store_true",
        help="Optional: add ansible_become=true on [all] host lines",
    )
    return p.parse_args()


def load_nodes(path: str) -> Dict[str, Dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, dict) or not data:
        raise ValueError("Input JSON must be a non-empty object keyed by hostname")

    # Validate schema
    for host, v in data.items():
        if not isinstance(host, str) or not host:
            raise ValueError(f"Invalid hostname key: {host!r}")
        if not isinstance(v, dict):
            raise ValueError(f"Host '{host}' value must be an object")
        if "ip" not in v or "role" not in v:
            raise ValueError(f"Host '{host}' must have 'ip' and 'role'")
        if not isinstance(v["ip"], str) or not v["ip"]:
            raise ValueError(f"Host '{host}' has invalid ip")
        if v["role"] not in ("control", "worker"):
            raise ValueError(f"Host '{host}' role must be 'control' or 'worker'")

    return data


def host_sort_key(name: str) -> Tuple[str, int]:
    # master-01, worker-03 gibi isimleri daha stabil sıralamak için
    # (sondaki sayıyı yakalamaya çalışır)
    import re

    m = re.search(r"(\d+)$", name)
    n = int(m.group(1)) if m else 0
    prefix = name[: m.start(1)] if m else name
    return (prefix, n)


def render_inventory(
    nodes: Dict[str, Dict[str, Any]],
    ansible_user: str,
    ansible_port: str,
    become: bool,
) -> str:
    controls: List[str] = []
    workers: List[str] = []

    for host in sorted(nodes.keys(), key=host_sort_key):
        role = nodes[host]["role"]
        if role == "control":
            controls.append(host)
        else:
            workers.append(host)

    if len(controls) == 0:
        raise ValueError("No control-plane nodes found (role=control).")
    if len(workers) == 0:
        raise ValueError("No worker nodes found (role=worker).")

    lines: List[str] = []

    # [all]
    lines.append("[all]")
    for host in sorted(nodes.keys(), key=host_sort_key):
        ip = nodes[host]["ip"]

        # Kubespray template’lerinde genelde ansible_host + ip kullanılır.
        # ip: Kubernetes servislerinin bind edeceği IP (çoğunlukla private IP)
        parts = [
            host,
            f"ansible_host={ip}",
            f"ip={ip}",
            f"ansible_port={ansible_port}",
        ]
        if ansible_user:
            parts.append(f"ansible_user={ansible_user}")
        if become:
            parts.append("ansible_become=true")

        # etcd üyesi olanlara etcd_member_name vermek pratik
        if host in controls:
            parts.append(f"etcd_member_name={host}")

        lines.append(" ".join(parts))

    lines.append("")  # blank line

    # control plane
    lines.append("[kube_control_plane]")
    lines.extend(controls)
    lines.append("")

    # etcd (stacked etcd = control plane üstünde)
    lines.append("[etcd]")
    lines.extend(controls)
    lines.append("")

    # workers
    lines.append("[kube_node]")
    lines.extend(workers)
    lines.append("")

    # optional group (ok to be empty)
    lines.append("[calico_rr]")
    lines.append("")

    # cluster children
    lines.append("[k8s_cluster:children]")
    lines.append("kube_control_plane")
    lines.append("kube_node")
    lines.append("calico_rr")
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    args = parse_args()

    nodes = load_nodes(args.input)
    content = render_inventory(
        nodes=nodes,
        ansible_user=args.ansible_user,
        ansible_port=str(args.ansible_port),
        become=bool(args.become),
    )

    out_dir = os.path.dirname(os.path.abspath(args.output))
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(content)

    with open(os.path.join(out_dir, ".gitignore"), "w", encoding="utf-8") as f:
        f.write("*\n")

    print(f"Wrote: {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise SystemExit(1)
