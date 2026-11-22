import json

from scripts import sla_report


def test_baseline_reproduces_report_gaps():
    metrics = json.load(open("data/baseline-metrics.json"))["metrics"]
    rows = {r["metric"]: r for r in sla_report.evaluate(metrics)}

    assert not rows["Uptime (30 days)"]["compliant"]
    assert rows["Uptime (30 days)"]["gap"] == 1.2
    assert not rows["Server response time (p95)"]["compliant"]
    assert rows["Server response time (p95)"]["gap"] == 20
    assert not rows["Load balancer capacity"]["compliant"]
    assert rows["Load balancer capacity"]["gap"] == 10

    assert rows["Bandwidth (monthly)"]["compliant"]
    assert rows["Inter-region latency"]["compliant"]
    assert rows["Error rate (per day)"]["compliant"]


def test_downtime_math():
    # 98.3% over 30 days ~= 734 min (~0.5 day); SLA allows 216 min (0.15 day)
    assert round(sla_report.downtime_minutes(98.3)) == 734
    assert round(sla_report.downtime_minutes(99.5)) == 216


def test_exit_codes():
    assert sla_report.main(["data/baseline-metrics.json"]) == 1
    assert sla_report.main(["data/target-state-metrics.json"]) == 0


def test_markdown_output(capsys):
    sla_report.main(["data/baseline-metrics.json", "--format", "markdown"])
    out = capsys.readouterr().out
    assert out.startswith("| Metric |")
    assert "❌" in out and "✅" in out
