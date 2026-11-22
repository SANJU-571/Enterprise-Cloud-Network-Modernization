#!/usr/bin/env python3
"""
SLA compliance report.

Compares a metrics snapshot against the Stratos Cloud SLA and prints a gap
table (the same analysis as the Week 3 network performance review), as text
or Markdown. Exits 1 if any SLA is breached so it can gate a CI job or a
scheduled check.

Usage:
    python scripts/sla_report.py data/baseline-metrics.json
    python scripts/sla_report.py data/baseline-metrics.json --format markdown
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class SlaRule:
    key: str
    label: str
    threshold: float
    higher_is_better: bool
    unit: str

    def evaluate(self, value: float) -> tuple[bool, float]:
        """Return (compliant, gap). Gap is positive when the SLA is missed."""
        if self.higher_is_better:
            gap = self.threshold - value
        else:
            gap = value - self.threshold
        return gap <= 0, gap


SLA_RULES: list[SlaRule] = [
    SlaRule("uptime_pct", "Uptime (30 days)", 99.5, True, "%"),
    SlaRule("response_time_p95_ms", "Server response time (p95)", 200, False, "ms"),
    SlaRule("bandwidth_monthly_gb", "Bandwidth (monthly)", 15000, False, "GB"),
    SlaRule("interregion_latency_ms", "Inter-region latency", 100, False, "ms"),
    SlaRule("errors_per_day", "Error rate (per day)", 10, False, ""),
    SlaRule("lb_capacity_pct", "Load balancer capacity", 85, False, "%"),
]


def downtime_minutes(uptime_pct: float, days: int = 30) -> float:
    """Minutes of downtime implied by an uptime percentage over `days`."""
    return (100 - uptime_pct) / 100 * days * 24 * 60


def evaluate(metrics: dict[str, float]) -> list[dict]:
    rows = []
    for rule in SLA_RULES:
        if rule.key not in metrics:
            continue
        value = float(metrics[rule.key])
        ok, gap = rule.evaluate(value)
        rows.append(
            {
                "metric": rule.label,
                "value": value,
                "target": rule.threshold,
                "unit": rule.unit,
                "compliant": ok,
                "gap": round(gap, 3),
                "direction": ">=" if rule.higher_is_better else "<=",
            }
        )
    return rows


def render_text(rows: list[dict], metrics: dict) -> str:
    out = [f"{'Metric':32} {'Current':>14} {'SLA':>14}  Status"]
    out.append("-" * 72)
    for r in rows:
        status = "OK" if r["compliant"] else f"BREACH (gap {r['gap']:g} {r['unit']})"
        out.append(
            f"{r['metric']:32} {r['value']:>11g} {r['unit']:<3}"
            f"{r['direction']:>3}{r['target']:>8g} {r['unit']:<3} {status}"
        )
    if "uptime_pct" in metrics:
        actual = downtime_minutes(metrics["uptime_pct"])
        allowed = downtime_minutes(99.5)
        out.append("")
        out.append(f"Downtime in 30 days: {actual:.0f} min (allowed {allowed:.0f} min)")
    return "\n".join(out)


def render_markdown(rows: list[dict], metrics: dict) -> str:
    out = ["| Metric | Current | SLA | Status |", "|---|---|---|---|"]
    for r in rows:
        status = "✅ Meets SLA" if r["compliant"] else f"❌ Gap: {r['gap']:g} {r['unit']}"
        out.append(
            f"| {r['metric']} | {r['value']:g} {r['unit']} | "
            f"{r['direction']} {r['target']:g} {r['unit']} | {status} |"
        )
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("metrics_file", type=Path)
    parser.add_argument("--format", choices=["text", "markdown", "json"], default="text")
    args = parser.parse_args(argv)

    metrics = json.loads(args.metrics_file.read_text())["metrics"]
    rows = evaluate(metrics)

    if args.format == "json":
        print(json.dumps(rows, indent=2))
    elif args.format == "markdown":
        print(render_markdown(rows, metrics))
    else:
        print(render_text(rows, metrics))

    return 0 if all(r["compliant"] for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
