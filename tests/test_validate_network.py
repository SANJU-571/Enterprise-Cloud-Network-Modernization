import copy

from scripts import validate_network as vn

PLAN = vn.load_plan(vn.ROOT / "network/addressing/vlans.yaml")


def test_repo_plan_and_configs_are_valid():
    assert vn.main([]) == 0


def test_detects_overlap():
    plan = copy.deepcopy(PLAN)
    plan["vlans"][1]["subnet"] = plan["vlans"][0]["subnet"]
    assert any("Overlap" in e for e in vn.check_plan(plan))


def test_detects_undersized_subnet():
    plan = copy.deepcopy(PLAN)
    plan["vlans"][0]["hosts"] = 500
    assert any("usable addresses" in e for e in vn.check_plan(plan))


def test_detects_aws_overlap():
    plan = copy.deepcopy(PLAN)
    plan["summary"] = "10.0.0.0/8"
    assert any("overlaps AWS" in e for e in vn.check_plan(plan))


def test_parse_svis():
    cfg = "interface Vlan10\n ip address 10.10.10.2 255.255.255.0\n standby 10 ip 10.10.10.1\n standby 10 priority 110\n!\n"
    assert vn.parse_svis(cfg)[10] == {"ip": "10.10.10.2", "vip": "10.10.10.1", "priority": 110}
