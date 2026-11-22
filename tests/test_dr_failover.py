from datetime import UTC, datetime, timedelta

from scripts import dr_failover as dr

ARN = "arn:aws:rds:ca-central-1:111122223333:db:stratos-prod-pg"


class FakeRds:
    def __init__(self, lag_min=5):
        self.lag = lag_min
        self.restored = None

    def describe_db_instance_automated_backups(self):
        return {"DBInstanceAutomatedBackups": [{
            "DBInstanceArn": ARN,
            "Status": "replicating",
            "DBInstanceAutomatedBackupsArn": "arn:aws:rds:ca-west-1:111122223333:auto-backup:ab-1",
            "RestoreWindow": {"LatestTime": datetime.now(UTC) - timedelta(minutes=self.lag)},
        }]}

    def restore_db_instance_to_point_in_time(self, **kw):
        self.restored = kw

    def get_waiter(self, name):
        class W:
            def wait(self, **kw):
                pass
        return W()


class FakeAsg:
    def __init__(self):
        self.updated = None

    def update_auto_scaling_group(self, **kw):
        self.updated = kw


class FakeElb:
    def describe_target_health(self, **kw):
        return {"TargetHealthDescriptions": [{"TargetHealth": {"State": "healthy"}}] * 3}


class FakeR53:
    def __init__(self):
        self.inverted = None

    def update_health_check(self, **kw):
        self.inverted = kw


class FakeSession:
    def __init__(self, rds):
        self.c = {"rds": rds, "autoscaling": FakeAsg(), "elbv2": FakeElb(), "route53": FakeR53()}

    def client(self, name):
        return self.c[name]


def test_dry_run_changes_nothing():
    rds = FakeRds()
    s = FakeSession(rds)
    report = dr.run(dr.FailoverPlan(source_db_arn=ARN), session=s)
    assert report["executed"] is False
    assert rds.restored is None
    assert s.c["autoscaling"].updated is None
    assert report["rpo_met"]


def test_execute_restores_scales_and_flips_dns():
    rds = FakeRds()
    s = FakeSession(rds)
    plan = dr.FailoverPlan(source_db_arn=ARN, execute=True, target_group_arn="tg", health_check_id="hc-1")
    report = dr.run(plan, session=s)
    assert rds.restored["MultiAZ"] is True
    assert rds.restored["UseLatestRestorableTime"] is True
    assert s.c["autoscaling"].updated["DesiredCapacity"] == 3
    assert s.c["route53"].inverted == {"HealthCheckId": "hc-1", "Inverted": True}
    assert report["rto_met"] and report["rpo_met"]


def test_rpo_breach_reported():
    report = dr.run(dr.FailoverPlan(source_db_arn=ARN), session=FakeSession(FakeRds(lag_min=30)))
    assert report["rpo_met"] is False


def test_compute_rpo_minutes():
    now = datetime(2026, 7, 1, 12, 0, tzinfo=UTC)
    assert dr.compute_rpo_minutes(now - timedelta(minutes=12), now) == 12
