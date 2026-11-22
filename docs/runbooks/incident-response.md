# Runbook: SLA Alert Response

Use this when a Prometheus or CloudWatch SLA alert fires.

## Triage by alert

| Alert | First checks | Typical fix |
|---|---|---|
| `EndpointDown` / Route 53 health check failing | ALB healthy host count, recent deploys, AZ health | Roll back the deploy; if regional, follow [dr-drill.md](dr-drill.md) |
| `ResponseTimeP95High` / `sla-latency-p95` | Redis hit rate, RDS CPU and Performance Insights top SQL, ASG at max? | Raise ASG max, warm the cache, add an index, scale RDS instance class |
| `LoadBalancerCapacityHigh` / `sla-lb-capacity` | Requests per target, ASG scaling activity | Confirm scaling isn't blocked (max reached, launch failures); raise max |
| `ErrorBudgetBurn` / `sla-errors-daily` | ALB 5xx vs target 5xx, app logs | Fix the failing dependency; roll back |
| `InterRegionLatencyHigh` | VPN tunnel state, ISP SD-WAN SLA on FortiGate | Fail over to the other ISP/tunnel; open a carrier ticket |
| `HAProxyBackendDown` | HAProxy stats page (`:8404/stats`) | Restart the backend service; check the keepalived master |
| `vpn-*-down` | Both tunnels down? Customer gateway reachable? | Check ISR IKE SAs (`show crypto ikev2 sa`), ISP status |

## Severity

| Sev | Definition | Response |
|---|---|---|
| 1 | Customer-facing outage or SLA breach in progress | Page on-call, incident commander, updates every 30 min |
| 2 | Early-warning threshold crossed, SLA at risk | On-call acknowledges within 15 min |
| 3 | Capacity / hygiene | Next business day |

## Post-incident
- Blameless review within 5 business days
- Update thresholds or runbooks if the alert was noisy or late
