# Runbook: Regional DR Drill / Failover

**Owner:** Cloud Operations · **Frequency:** quarterly drill, or on a declared regional outage
**Targets:** RTO < 4 h · RPO < 15 min

## Preconditions
- [ ] DR Terraform applied (`terraform/environments/dr`) and the plan is clean
- [ ] Replicated automated backups visible in `ca-west-1`
- [ ] S3 replication metrics show no backlog older than 15 min
- [ ] Drill announced to stakeholders (planned drills only)
- [ ] Engineer has the `DevOps` group with an MFA session

## Steps

| # | Action | Command / location | Expected |
|---|---|---|---|
| 1 | Start the incident timer and open the incident channel | — | T0 recorded |
| 2 | Check replication status and RPO | `python scripts/dr_failover.py --source-db-arn <ARN>` | "RPO x min" ≤ 15 |
| 3 | Run the failover | add `--execute --target-group-arn … --db-security-group … --health-check-id …` | DB available, ASG at 3, targets healthy |
| 4 | Point the app at the restored DB | Update the DB host in SSM Parameter Store and run an ASG instance refresh | `/healthz` 200 from DR ALB |
| 5 | Verify DNS | `dig portal.example.com` | Resolves to the DR ALB |
| 6 | Smoke tests | Log in, list services, create a record | All pass |
| 7 | Record timings | Output of step 3 | Fill in the drill log in `docs/disaster-recovery.md` |
| 8 | Fail back (drill) | Reverse the procedure; un-invert the health check; scale DR ASG to 0; delete the restored DB after a final snapshot | Primary serving, DR idle |

## Abort criteria
- RPO > 15 min with no replication backlog explanation: escalate before continuing
- DR targets not healthy after 30 min: the script times out; inspect launch template/user data logs

## After the drill
- Write up the measured RTO/RPO, issues and actions
- Update this runbook if any step was unclear
