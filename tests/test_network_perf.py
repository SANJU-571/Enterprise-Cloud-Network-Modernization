import json

from scripts import network_perf as npf

PING = """PING 10.20.64.10 (10.20.64.10) 56(84) bytes of data.
64 bytes from 10.20.64.10: icmp_seq=1 ttl=62 time=40.0 ms
64 bytes from 10.20.64.10: icmp_seq=2 ttl=62 time=44.0 ms
64 bytes from 10.20.64.10: icmp_seq=3 ttl=62 time=42.0 ms

--- 10.20.64.10 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 402ms
"""


def test_parse_ping():
    r = npf.parse_ping(PING)
    assert r == {"latency_ms": 42.0, "jitter_ms": 3.0, "loss_pct": 0.0, "samples": 3}


def test_parse_ping_all_lost():
    r = npf.parse_ping("3 packets transmitted, 0 received, 100% packet loss")
    assert r["latency_ms"] is None and r["loss_pct"] == 100.0


def test_parse_iperf():
    out = json.dumps({"end": {"sum_received": {"bits_per_second": 941_000_000}}})
    assert npf.parse_iperf(out) == 941.0


def test_grade():
    g = npf.grade({"latency_ms": 42, "jitter_ms": 3, "loss_pct": 0, "throughput_mbps": 700}, link_mbps=1000)
    assert g == {"latency": True, "jitter": True, "loss": True, "throughput": False}
