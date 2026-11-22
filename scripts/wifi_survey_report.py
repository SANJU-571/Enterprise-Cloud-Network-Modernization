#!/usr/bin/env python3
"""
Summarise a Wi-Fi site survey against the design target (RSSI >= -67 dBm).

Usage:
    python scripts/wifi_survey_report.py network/wireless/site-survey-results.csv
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path

TARGET_RSSI = -67


def classify(rssi: int) -> str:
    if rssi >= -60:
        return "Excellent"
    if rssi >= -67:
        return "Good"
    if rssi >= -72:
        return "Moderate"
    return "Poor"


def load(path: Path) -> list[dict]:
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        r["avg_rssi_dbm"] = int(r["avg_rssi_dbm"])
        r["floor"] = int(r["floor"])
    return rows


def summarise(rows: list[dict], target: int = TARGET_RSSI) -> dict:
    by_floor: dict[int, list[dict]] = defaultdict(list)
    for r in rows:
        by_floor[r["floor"]].append(r)

    floors = {}
    for floor, areas in sorted(by_floor.items()):
        rssis = [a["avg_rssi_dbm"] for a in areas]
        floors[floor] = {
            "areas": len(areas),
            "avg_rssi": round(sum(rssis) / len(rssis), 1),
            "worst_rssi": min(rssis),
            "below_target": [a["area"] for a in areas if a["avg_rssi_dbm"] < target],
        }
    failing = [r for r in rows if r["avg_rssi_dbm"] < target]
    return {"target": target, "floors": floors, "failing": failing, "passed": not failing}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("survey_csv", type=Path)
    ap.add_argument("--target", type=int, default=TARGET_RSSI)
    args = ap.parse_args(argv)

    rows = load(args.survey_csv)
    s = summarise(rows, args.target)

    print(f"Design target: RSSI >= {s['target']} dBm\n")
    print(f"{'Floor':<6}{'Area':<18}{'AP':<14}{'RSSI':>6}  {'Class':<10}Recommendation")
    for r in rows:
        mark = "" if r["avg_rssi_dbm"] >= s["target"] else "  <-- below target"
        print(
            f"{r['floor']:<6}{r['area']:<18}{r['ap_model']:<14}{r['avg_rssi_dbm']:>6}  "
            f"{classify(r['avg_rssi_dbm']):<10}{r['recommendation']}{mark}"
        )
    print()
    for floor, f in s["floors"].items():
        print(f"Floor {floor}: avg {f['avg_rssi']} dBm, worst {f['worst_rssi']} dBm, "
              f"{len(f['below_target'])} area(s) below target")

    return 0 if s["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
