#!/usr/bin/env python3
"""
Regional failover: ca-central-1 (Montreal) -> ca-west-1 (Calgary).

Steps (each is timed so the run doubles as an RTO measurement in DR drills):
  1. Pre-checks       - confirm DR replicated backups exist and find the latest
                        restorable time (RPO)
  2. Restore database - point-in-time restore from the replicated automated
                        backups into the DR subnet group
  3. Scale compute    - raise the DR ASG from 0 to the production minimum
  4. Wait healthy     - poll the DR target group until enough targets are healthy
  5. DNS              - Route 53 failover records switch automatically once the
                        primary health check fails; --force-dns flips the
                        primary health check off for planned drills
  6. Report           - print measured RTO and RPO against targets

Dry run is the default. Nothing changes without --execute.

Usage:
    python scripts/dr_failover.py --source-db-arn arn:aws:rds:ca-central-1:...:db:stratos-prod-pg
    python scripts/dr_failover.py --source-db-arn ... --execute
"""

from __future__ import annotations

import argparse
import logging
import sys
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime

RTO_TARGET_MIN = 240  # < 4 hours
RPO_TARGET_MIN = 15   # < 15 minutes

log = logging.getLogger("dr-failover")


@dataclass
class FailoverPlan:
    source_db_arn: str
    dr_region: str = "ca-west-1"
    target_db_id: str = "stratos-dr-pg"
    db_subnet_group: str = "stratos-dr-db"
    db_security_group: str | None = None
    db_instance_class: str = "db.m6g.large"
    asg_name: str = "stratos-dr-asg"
    asg_capacity: int = 3
    target_group_arn: str | None = None
    health_check_id: str | None = None
    execute: bool = False
    timings: dict[str, float] = field(default_factory=dict)


class Step:
    def __init__(self, plan: FailoverPlan, name: str) -> None:
        self.plan, self.name = plan, name

    def __enter__(self) -> Step:
        self.t0 = time.monotonic()
        log.info("==> %s%s", self.name, "" if self.plan.execute else " (dry run)")
        return self

    def __exit__(self, *exc) -> None:
        self.plan.timings[self.name] = time.monotonic() - self.t0


def compute_rpo_minutes(latest_restorable: datetime, now: datetime | None = None) -> float:
    now = now or datetime.now(UTC)
    return (now - latest_restorable).total_seconds() / 60


def find_replicated_backup(rds, source_db_arn: str) -> dict:
    resp = rds.describe_db_instance_automated_backups()
    for b in resp.get("DBInstanceAutomatedBackups", []):
        if b.get("DBInstanceArn") == source_db_arn and b.get("Status") in ("replicating", "active"):
            return b
    raise RuntimeError(f"No replicated automated backup found for {source_db_arn}")


def run(plan: FailoverPlan, session=None) -> dict:
    import boto3

    session = session or boto3.Session(region_name=plan.dr_region)
    rds = session.client("rds")
    asg = session.client("autoscaling")
    elb = session.client("elbv2")
    r53 = session.client("route53")

    with Step(plan, "pre-checks"):
        backup = find_replicated_backup(rds, plan.source_db_arn)
        latest = backup["RestoreWindow"]["LatestTime"]
        rpo = compute_rpo_minutes(latest)
        log.info("Replicated backup %s, latest restorable %s (RPO %.1f min)",
                 backup["DBInstanceAutomatedBackupsArn"], latest.isoformat(), rpo)
        if rpo > RPO_TARGET_MIN:
            log.warning("RPO %.1f min exceeds %d min target", rpo, RPO_TARGET_MIN)

    with Step(plan, "restore-database"):
        params = dict(
            SourceDBInstanceAutomatedBackupsArn=backup["DBInstanceAutomatedBackupsArn"],
            TargetDBInstanceIdentifier=plan.target_db_id,
            UseLatestRestorableTime=True,
            DBInstanceClass=plan.db_instance_class,
            DBSubnetGroupName=plan.db_subnet_group,
            MultiAZ=True,
            PubliclyAccessible=False,
            DeletionProtection=True,
            CopyTagsToSnapshot=True,
        )
        if plan.db_security_group:
            params["VpcSecurityGroupIds"] = [plan.db_security_group]
        if plan.execute:
            rds.restore_db_instance_to_point_in_time(**params)
            log.info("Waiting for %s to become available...", plan.target_db_id)
            rds.get_waiter("db_instance_available").wait(
                DBInstanceIdentifier=plan.target_db_id,
                WaiterConfig={"Delay": 30, "MaxAttempts": 240},
            )
        else:
            log.info("Would restore with %s", params)

    with Step(plan, "scale-compute"):
        if plan.execute:
            asg.update_auto_scaling_group(
                AutoScalingGroupName=plan.asg_name,
                MinSize=plan.asg_capacity,
                DesiredCapacity=plan.asg_capacity,
            )
        log.info("ASG %s -> min/desired %d", plan.asg_name, plan.asg_capacity)

    with Step(plan, "wait-healthy"):
        if plan.execute and plan.target_group_arn:
            deadline = time.monotonic() + 30 * 60
            while time.monotonic() < deadline:
                health = elb.describe_target_health(TargetGroupArn=plan.target_group_arn)
                healthy = sum(
                    1 for t in health["TargetHealthDescriptions"]
                    if t["TargetHealth"]["State"] == "healthy"
                )
                log.info("Healthy targets: %d/%d", healthy, plan.asg_capacity)
                if healthy >= plan.asg_capacity:
                    break
                time.sleep(20)
            else:
                raise TimeoutError("DR targets did not become healthy in 30 minutes")

    with Step(plan, "dns"):
        if plan.health_check_id:
            if plan.execute:
                # Inverting the primary health check forces Route 53 to SECONDARY
                r53.update_health_check(HealthCheckId=plan.health_check_id, Inverted=True)
            log.info("Primary health check %s inverted -> traffic to DR", plan.health_check_id)
        else:
            log.info("Relying on automatic Route 53 failover (primary health check)")

    total_min = sum(plan.timings.values()) / 60
    report = {
        "executed": plan.execute,
        "rto_minutes": round(total_min, 1),
        "rto_target_minutes": RTO_TARGET_MIN,
        "rto_met": total_min <= RTO_TARGET_MIN,
        "rpo_minutes": round(rpo, 1),
        "rpo_target_minutes": RPO_TARGET_MIN,
        "rpo_met": rpo <= RPO_TARGET_MIN,
        "steps_seconds": {k: round(v, 1) for k, v in plan.timings.items()},
    }
    return report


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source-db-arn", required=True)
    ap.add_argument("--dr-region", default="ca-west-1")
    ap.add_argument("--asg-name", default="stratos-dr-asg")
    ap.add_argument("--asg-capacity", type=int, default=3)
    ap.add_argument("--db-subnet-group", default="stratos-dr-db")
    ap.add_argument("--db-security-group")
    ap.add_argument("--target-group-arn")
    ap.add_argument("--health-check-id", help="Primary Route 53 health check (planned drills)")
    ap.add_argument("--execute", action="store_true", help="Actually perform the failover")
    args = ap.parse_args(argv)

    plan = FailoverPlan(
        source_db_arn=args.source_db_arn,
        dr_region=args.dr_region,
        asg_name=args.asg_name,
        asg_capacity=args.asg_capacity,
        db_subnet_group=args.db_subnet_group,
        db_security_group=args.db_security_group,
        target_group_arn=args.target_group_arn,
        health_check_id=args.health_check_id,
        execute=args.execute,
    )
    report = run(plan)

    log.info("RTO %.1f min (target < %d) | RPO %.1f min (target < %d)",
             report["rto_minutes"], RTO_TARGET_MIN, report["rpo_minutes"], RPO_TARGET_MIN)
    return 0 if report["rto_met"] and report["rpo_met"] else 2


if __name__ == "__main__":
    sys.exit(main())
