#!/usr/bin/env python3
"""
Validate the campus addressing plan (network/addressing/vlans.yaml) and the
Cisco configs against it.

Checks
  1. Every VLAN subnet sits inside the site summary prefix
  2. No two VLAN / transit subnets overlap
  3. Each subnet is large enough for its declared host count (+20% growth)
  4. On-prem summary does not overlap the AWS VPC ranges
  5. Every VLAN in the plan has an SVI with HSRP .1 VIP on both core switches,
     with the correct active / standby priorities
  6. No VTY line accepts telnet

Exit code 1 on any failure - wired into CI.
"""

from __future__ import annotations

import argparse
import ipaddress
import re
import sys
from itertools import combinations
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
AWS_RANGES = [ipaddress.ip_network("10.20.0.0/16"), ipaddress.ip_network("10.30.0.0/16")]
GROWTH = 1.2


def load_plan(path: Path) -> dict:
    return yaml.safe_load(path.read_text())


def check_plan(plan: dict) -> list[str]:
    errors: list[str] = []
    summary = ipaddress.ip_network(plan["summary"])
    nets: list[tuple[str, ipaddress.IPv4Network]] = []

    for v in plan["vlans"]:
        net = ipaddress.ip_network(v["subnet"])
        label = f"VLAN {v['id']} ({v['name']})"
        nets.append((label, net))

        if not net.subnet_of(summary):
            errors.append(f"{label}: {net} is outside summary {summary}")

        usable = net.num_addresses - 2 - 3  # network, broadcast, HSRP VIP + 2 SVIs
        needed = int(v["hosts"] * GROWTH)
        if usable < needed:
            errors.append(f"{label}: {usable} usable addresses < {needed} required (hosts x {GROWTH})")

    for t in plan.get("transit", []):
        nets.append((t["name"], ipaddress.ip_network(t["subnet"])))

    for (a_label, a), (b_label, b) in combinations(nets, 2):
        if a.overlaps(b):
            errors.append(f"Overlap: {a_label} {a} <-> {b_label} {b}")

    for aws in AWS_RANGES:
        if summary.overlaps(aws):
            errors.append(f"On-prem summary {summary} overlaps AWS range {aws}")

    return errors


def parse_svis(cfg: str) -> dict[int, dict]:
    """Return {vlan_id: {"ip": str, "vip": str|None, "priority": int|None}}."""
    svis: dict[int, dict] = {}
    for block in re.split(r"\n!\n|\n!", cfg):
        m = re.search(r"^interface Vlan(\d+)$", block, re.M)
        if not m:
            continue
        vid = int(m.group(1))
        ip = re.search(r"^ ip address (\S+) \S+", block, re.M)
        vip = re.search(r"^ standby \d+ ip (\S+)", block, re.M)
        prio = re.search(r"^ standby \d+ priority (\d+)", block, re.M)
        svis[vid] = {
            "ip": ip.group(1) if ip else None,
            "vip": vip.group(1) if vip else None,
            "priority": int(prio.group(1)) if prio else None,
        }
    return svis


def check_core_configs(plan: dict, cisco_dir: Path) -> list[str]:
    errors: list[str] = []
    hsrp = plan["hsrp"]
    expected = {
        "core-sw1.cfg": (2, hsrp["active_priority"]),
        "core-sw2.cfg": (3, hsrp["standby_priority"]),
    }
    for fname, (host_octet, prio) in expected.items():
        path = cisco_dir / fname
        if not path.exists():
            errors.append(f"{fname}: missing")
            continue
        svis = parse_svis(path.read_text())
        for v in plan["vlans"]:
            net = ipaddress.ip_network(v["subnet"])
            vid = v["id"]
            svi = svis.get(vid)
            if svi is None:
                errors.append(f"{fname}: no SVI for VLAN {vid}")
                continue
            want_ip = str(net.network_address + host_octet)
            want_vip = str(net.network_address + 1)
            if svi["ip"] != want_ip:
                errors.append(f"{fname}: VLAN {vid} SVI {svi['ip']} != expected {want_ip}")
            if svi["vip"] != want_vip:
                errors.append(f"{fname}: VLAN {vid} HSRP VIP {svi['vip']} != expected {want_vip}")
            if svi["priority"] != prio:
                errors.append(f"{fname}: VLAN {vid} HSRP priority {svi['priority']} != {prio}")
    return errors


def check_no_telnet(cisco_dir: Path) -> list[str]:
    errors = []
    for cfg in sorted(cisco_dir.glob("*.cfg")):
        text = cfg.read_text()
        for m in re.finditer(r"^ transport input (.+)$", text, re.M):
            if "telnet" in m.group(1) or m.group(1).strip() == "all":
                errors.append(f"{cfg.name}: VTY allows '{m.group(1).strip()}' (SSH only)")
    return errors


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", type=Path, default=ROOT / "network/addressing/vlans.yaml")
    ap.add_argument("--cisco-dir", type=Path, default=ROOT / "network/cisco")
    args = ap.parse_args(argv)

    plan = load_plan(args.plan)
    errors = check_plan(plan) + check_core_configs(plan, args.cisco_dir) + check_no_telnet(args.cisco_dir)

    if errors:
        print(f"FAIL - {len(errors)} problem(s):")
        for e in errors:
            print(f"  - {e}")
        return 1

    print(f"OK - {len(plan['vlans'])} VLANs, HSRP and VTY checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
