#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Terraform output.json -> Kubespray inventory.ini generator
Supports bastion host with public IP for SSH proxy
"""

import argparse
import json
import os
import re
import sys
from typing import Any, Dict, List, Tuple

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate Kubespray inventory.ini")
    p.add_argument("-i", "--input", default="artifacts/nodes.json")
    p.add_argument("-o", "--output", default="ansible/inventory/inventory.ini")
    p.add_argument("--ansible-user", default="debian")
    p.add_argument("--ansible-port", default="22")
    p.add_argument("--become", action="store_true", default=True)
    return p.parse_args()

def load_nodes(path: str) -> Dict[str, Dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data

def host_sort_key(name: str) -> Tuple[str, int]:
    m = re.search(r"(\d+)$", name)
    n = int(m.group(1)) if m else 0
    prefix = name[: m.start(1)] if m else name
    return (prefix, n)

def render_inventory(nodes: Dict[str, Dict[str, Any]], ansible_user: str, ansible_port: str, become: bool) -> str:
    controls = []
    workers = []
    bastion_info = None

    # Classify nodes by role and find bastion
    for host in sorted(nodes.keys(), key=host_sort_key):
        role = nodes[host]["role"]
        if role == "control":
            controls.append(host)
        elif role == "worker":
            workers.append(host)
        elif role == "standalone" and host == "bastion":
            bastion_info = {
                "name": host,
                "private_ip": nodes[host]["ip"],
                "public_ip": nodes[host].get("public_ip")
            }

    lines = []

    # [all] - cluster nodes only (bastion excluded - it's just a jump host)
    lines.append("[all]")
    
    for host in controls + workers:
        ip = nodes[host]["ip"]
        parts = [host, f"ansible_host={ip}", f"ip={ip}", f"ansible_port={ansible_port}"]
        if ansible_user:
            parts.append(f"ansible_user={ansible_user}")
        if become:
            parts.append("ansible_become=true")
        if host in controls:
            parts.append(f"etcd_member_name={host}")
        lines.append(" ".join(parts))

    lines.append("")

    # Kubernetes groups
    lines.append("[kube_control_plane]")
    lines.extend(controls)
    lines.append("")

    lines.append("[etcd]")
    lines.extend(controls)
    lines.append("")

    lines.append("[kube_node]")
    lines.extend(workers)
    lines.append("")

    lines.append("[calico_rr]")
    lines.append("")

    lines.append("[k8s_cluster:children]")
    lines.append("kube_control_plane")
    lines.append("kube_node")
    lines.append("calico_rr")
    lines.append("")

    # ProxyJump via bastion (if public IP exists)
    if bastion_info and bastion_info["public_ip"]:
        lines.append("[k8s_cluster:vars]")
        proxy_cmd = f'-o ProxyCommand="ssh -W %h:%p -q -o StrictHostKeyChecking=no {ansible_user}@{bastion_info["public_ip"]}"'
        lines.append(f"ansible_ssh_common_args='{proxy_cmd} -o StrictHostKeyChecking=no'")
        lines.append("")

    return "\n".join(lines)

def main() -> int:
    args = parse_args()
    print(f"Loading nodes from: {args.input}")
    
    nodes = load_nodes(args.input)
    
    # Count and display nodes
    roles = {}
    bastion_ip = None
    for name, info in nodes.items():
        r = info["role"]
        roles[r] = roles.get(r, 0) + 1
        if name == "bastion" and info.get("public_ip"):
            bastion_ip = info["public_ip"]
    
    print(f"Found nodes: {roles}")
    if bastion_ip:
        print(f"Bastion public IP: {bastion_ip}")
        print("Using SSH ProxyJump via bastion")
    
    content = render_inventory(nodes, args.ansible_user, str(args.ansible_port), args.become)
    
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(content)
    
    print(f"Inventory created: {args.output}")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
