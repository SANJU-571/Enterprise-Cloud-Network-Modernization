#!/usr/bin/env python3
"""
Capacity forecast (action plan task 3.3).

Fits a least-squares linear trend to monthly usage and reports, for each
metric, the month in which it will cross its planning threshold. Pure standard
library so it runs anywhere (jump host, CI, Lambda).

Usage:
    python scripts/capacity_forecast.py data/monthly-usage.csv
    python scripts/capacity_forecast.py data/monthly-usage.csv --threshold bandwidth_gb=15000
"""

from __future__ import annotations

import argparse
import csv
import math
import sys
from datetime import date
from pathlib import Path

# Planning thresholds = 85% of the hard limit, mirroring the LB capacity SLA
DEFAULT_THRESHOLDS = {
    "bandwidth_gb": 15000 * 0.85,  # monthly bandwidth SLA ceiling
    "peak_rps": 700 * 0.85,        # ~700 req/s design capacity at minimum ASG size
    "storage_tb": 30 * 0.85,
}


def linear_fit(ys: list[float]) -> tuple[float, float]:
    """Return (slope, intercept) for y = slope * x + intercept with x = 0..n-1."""
    n = len(ys)
    if n < 2:
        raise ValueError("need at least two data points")
    xs = range(n)
    mean_x = (n - 1) / 2
    mean_y = sum(ys) / n
    sxx = sum((x - mean_x) ** 2 for x in xs)
    sxy = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys, strict=False))
    slope = sxy / sxx
    return slope, mean_y - slope * mean_x


def add_months(d: date, months: int) -> date:
    y, m = divmod(d.month - 1 + months, 12)
    return date(d.year + y, m + 1, 1)


def months_until(ys: list[float], threshold: float) -> int | None:
    """Months after the last observation until the trend crosses threshold."""
    slope, intercept = linear_fit(ys)
    last_x = len(ys) - 1
    if ys[-1] >= threshold:
        return 0
    if slope <= 0:
        return None
    cross_x = (threshold - intercept) / slope
    return max(0, math.ceil(cross_x - last_x))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("usage_csv", type=Path)
    ap.add_argument("--threshold", action="append", default=[], help="metric=value override")
    args = ap.parse_args(argv)

    thresholds = dict(DEFAULT_THRESHOLDS)
    for t in args.threshold:
        k, v = t.split("=", 1)
        thresholds[k] = float(v)

    with args.usage_csv.open(newline="") as f:
        rows = list(csv.DictReader(f))
    last = date.fromisoformat(rows[-1]["month"] + "-01")

    print(f"Trend over {len(rows)} months (last: {last:%Y-%m})\n")
    print(f"{'Metric':<14}{'Latest':>10}{'Growth/mo':>12}{'Threshold':>12}  Crosses")
    for metric, limit in thresholds.items():
        if metric not in rows[0]:
            continue
        ys = [float(r[metric]) for r in rows]
        slope, _ = linear_fit(ys)
        m = months_until(ys, limit)
        when = "never (flat/declining)" if m is None else (
            "ALREADY OVER" if m == 0 else f"{add_months(last, m):%Y-%m} (in {m} mo)")
        print(f"{metric:<14}{ys[-1]:>10g}{slope:>12.1f}{limit:>12g}  {when}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
