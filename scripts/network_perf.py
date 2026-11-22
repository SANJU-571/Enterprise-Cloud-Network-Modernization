#!/usr/bin/env python3
"""
Wired network performance check (latency, jitter, packet loss, throughput).

Wraps `ping` and `iperf3` and grades results against the targets used in the
network performance programme:

    Latency      < 100 ms
    Jitter       < 30 ms
    Packet loss  < 1 %
    Throughput   >= 80 % of link speed

Usage:
    python scripts/network_perf.py --host 10.20.64.10
    python scripts/network_perf.py --host 10.10.100.40 --iperf --link-mbps 1000
    python scripts/network_perf.py --host 10.20.64.10 --csv results.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import statistics
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

TARGETS = {"latency_ms": 100.0, "jitter_ms": 30.0, "loss_pct": 1.0, "throughput_ratio": 0.8}


def parse_ping(output: str) -> dict:
    """Parse Linux iputils ping output into latency / jitter / loss."""
    rtts = [float(m) for m in re.findall(r"time=([\d.]+) ms", output)]
    loss_m = re.search(r"([\d.]+)% packet loss", output)
    loss = float(loss_m.group(1)) if loss_m else 100.0
    if not rtts:
        return {"latency_ms": None, "jitter_ms": None, "loss_pct": loss, "samples": 0}
    # Jitter = mean absolute difference between consecutive RTTs (RFC 3550 style)
    diffs = [abs(b - a) for a, b in zip(rtts, rtts[1:], strict=False)]
    return {
        "latency_ms": round(statistics.mean(rtts), 2),
        "jitter_ms": round(statistics.mean(diffs), 2) if diffs else 0.0,
        "loss_pct": loss,
        "samples": len(rtts),
    }


def parse_iperf(output: str) -> float:
    """Return received throughput in Mbit/s from `iperf3 -J` output."""
    data = json.loads(output)
    return round(data["end"]["sum_received"]["bits_per_second"] / 1e6, 1)


def grade(result: dict, link_mbps: float | None = None) -> dict[str, bool]:
    g = {}
    if result.get("latency_ms") is not None:
        g["latency"] = result["latency_ms"] < TARGETS["latency_ms"]
        g["jitter"] = result["jitter_ms"] < TARGETS["jitter_ms"]
    g["loss"] = result["loss_pct"] < TARGETS["loss_pct"]
    if link_mbps and result.get("throughput_mbps") is not None:
        g["throughput"] = result["throughput_mbps"] >= link_mbps * TARGETS["throughput_ratio"]
    return g


def run_ping(host: str, count: int) -> dict:
    out = subprocess.run(["ping", "-c", str(count), "-i", "0.2", host],
                         capture_output=True, text=True, check=False).stdout
    return parse_ping(out)


def run_iperf(host: str, seconds: int) -> float:
    if not shutil.which("iperf3"):
        raise RuntimeError("iperf3 not installed")
    out = subprocess.run(["iperf3", "-c", host, "-t", str(seconds), "-J"],
                         capture_output=True, text=True, check=True).stdout
    return parse_iperf(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", required=True)
    ap.add_argument("--count", type=int, default=50)
    ap.add_argument("--iperf", action="store_true")
    ap.add_argument("--seconds", type=int, default=10)
    ap.add_argument("--link-mbps", type=float)
    ap.add_argument("--csv", type=Path, help="Append results to a CSV log")
    args = ap.parse_args(argv)

    result = run_ping(args.host, args.count)
    if args.iperf:
        result["throughput_mbps"] = run_iperf(args.host, args.seconds)
    grades = grade(result, args.link_mbps)

    print(f"Target: {args.host}")
    for k, v in result.items():
        print(f"  {k:<16} {v}")
    for k, ok in grades.items():
        print(f"  {k:<16} {'PASS' if ok else 'FAIL'}")

    if args.csv:
        new = not args.csv.exists()
        with args.csv.open("a", newline="") as f:
            w = csv.writer(f)
            if new:
                w.writerow(["timestamp", "host", *result.keys()])
            w.writerow([datetime.now(UTC).isoformat(), args.host, *result.values()])

    return 0 if all(grades.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
