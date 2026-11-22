# Data files

| File | What it is |
|---|---|
| `baseline-metrics.json` | Performance measurements taken before remediation, used as input to the SLA gap analysis |
| `target-state-metrics.json` | Design targets / acceptance criteria the remediation is sized for. **Not a measurement.** CI asserts these meet every SLA |
| `monthly-usage.csv` | Illustrative monthly usage series used to demonstrate `scripts/capacity_forecast.py`. Replace it with exports from CloudWatch / Prometheus |
