# SLA & Network Performance Analysis

This analysis was the starting point of the modernization. Measured performance
was compared against the SLA. Each gap was traced to an infrastructure cause, and
a three-phase remediation plan was produced. The plan is implemented in this
repository.

Reproduce the gap table at any time:

```bash
python scripts/sla_report.py data/baseline-metrics.json
```

## 1. Baseline vs SLA

| Metric | Measured | SLA | Result |
|---|---|---|---|
| Uptime (last 30 days) | 29.5 days (**98.3%**) | ≥ 99.5% | ❌ **1.2 pts below**: ~734 min down vs 216 min allowed |
| Server response time (7-day avg) | **220 ms** | ≤ 200 ms for 95% of requests | ❌ **20 ms over** |
| Bandwidth (monthly) | 10,500 GB (peak day 600 GB, avg 350 GB/day) | ≤ 15,000 GB | ✅ 70% of allowance |
| Inter-DC latency (7 days) | 95 ms | ≤ 100 ms | ✅ but only 5 ms headroom |
| Error rate (30 days) | 245 total, 8.2/day | ≤ 10/day | ✅ |
| Load balancer throughput | **95% capacity** | ≤ 85% | ❌ **10 pts over** |

## 2. Impact of each gap

**Uptime (98.3%)**
- Clients lose access to services. This risks breaching client contracts and creates financial-loss claims.
- It damages the reputation of a provider whose main selling point is reliability.
- Incident handling and client communication put extra load on internal teams.

**Response time (220 ms)**
- Degraded experience on interactive and latency-sensitive apps, and lower productivity for clients running business-critical workloads.
- Higher bounce rates on public-facing apps.
- **Cascading failures**: slow responses cause upstream timeouts and request queuing, which slows everything else down.

**Load balancer (95%)**
- A near-saturated LB is a bottleneck and an effective single point of failure. It contributes directly to the response-time gap.
- There is almost no headroom for traffic spikes, so overload or outage is a real risk.

## 3. Root causes (infrastructure limitations)

| # | Limitation | Drives | Evidence |
|---|---|---|---|
| 1 | Insufficient redundancy and fault tolerance: no N+1/2N on compute, network or power in a zone, no redundant network paths, weak DB/storage replication | Uptime | Downtime episodes map to single-component failures |
| 2 | Server resource contention and application inefficiency: high CPU/memory at peak, slow SQL, blocking I/O, no caching | Response time | CPU > 70% / memory > 80% during peaks; top-10 slow queries dominate DB time |
| 3 | Under-provisioned, single LB: no active/active or active/passive pair | LB capacity, response time | 95% average throughput |
| 4 | No proactive scaling: manual scaling only, no metric-driven policies | All three under surges | Performance dips correlate with traffic spikes |

## 4. Remediation plan → implementation

### Phase 1: Immediate remediation (weeks 1–2)

| Task | What was planned | Where it is implemented |
|---|---|---|
| 1.1 LB capacity | Higher-tier / autoscaling LB in cloud. On-prem: second HAProxy node with keepalived VIP, tune `maxconn`, threads, `worker_processes`/`worker_connections` | `terraform/modules/compute` (managed ALB, ASG scale on requests-per-target at 80%), `load-balancer/haproxy`, `load-balancer/keepalived`, `load-balancer/nginx` |
| 1.2 Server tuning | Vertical scale servers > 70% CPU / 80% memory (m5.large → m5.xlarge), index the top-10 slow queries, right-size thread pools | `var.instance_type`, `aws_db_parameter_group.pg` (`log_min_duration_statement`, `pg_stat_statements`), `app/schema.sql` index, gunicorn workers/threads in user data |

### Phase 2: High availability and optimization (weeks 3–6)

| Task | What was planned | Where it is implemented |
|---|---|---|
| 2.1 HA for critical services | Multi-AZ DB with automatic failover; app in ≥ 2 AZs behind the LB with N healthy per AZ; redundant NICs/switches with LACP | RDS `multi_az = true`, ASG across 3 AZs with `min_size = 3`, NAT per AZ, core pair with LACP Port-channels and HSRP |
| 2.2 App and DB optimization | APM profiling, distributed cache (`if cache.get(key) … else db.query(); cache.set(key, data, ttl)`), connection-pool tuning | ElastiCache Redis module, `app/cache.py` (`CacheAside`), Prometheus latency histogram, Server-Timing header |

### Phase 3: Long-term strategy (ongoing)

| Task | What was planned | Where it is implemented |
|---|---|---|
| 3.1 DR plan and drills | Separate-region DR site, cross-region replication, automated failover, quarterly drills | `environments/dr`, S3 CRR + RTC, RDS backup replication, `scripts/dr_failover.py`, [disaster-recovery.md](disaster-recovery.md) |
| 3.2 Monitoring and alerting | Centralized metrics/logs/traces, SLA-driven alerts (`p95 > 180 ms for 5 min`, `LB > 80% for 10 min`), SLA dashboards | `terraform/modules/monitoring`, `monitoring/prometheus/rules/sla-alerts.yml`, `monitoring/grafana/sla-overview.json` |
| 3.3 Capacity planning | Monthly utilization reports, growth forecast, scaling policy reviews | `scripts/capacity_forecast.py`, `.github/workflows/sla-check.yml` |

## 5. Acceptance criteria

The remediated platform is accepted when a 30-day window (or an equivalent load
test plus DR drill) meets all of the following. `data/target-state-metrics.json`
encodes them, and CI checks them:

- Availability ≥ 99.5% (design target 99.9%)
- p95 response ≤ 200 ms at peak load (design target 160 ms)
- LB utilization ≤ 85% at peak (design target 65%)
- ≤ 10 server errors per day
- DR drill: RTO < 4 h and RPO < 15 min
