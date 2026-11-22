import pytest

from app.cache import CacheAside, MemoryBackend
from app.main import create_app


class Clock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


def test_memory_backend_expiry():
    clock = Clock()
    b = MemoryBackend(clock=clock)
    b.set("k", "v", ttl=10)
    assert b.get("k") == "v"
    clock.t = 10
    assert b.get("k") is None


def test_cache_aside_hits_after_first_load():
    calls = []
    cache = CacheAside(MemoryBackend())
    loader = lambda: calls.append(1) or [{"id": 1}]  # noqa: E731
    assert cache.get_or_set("x", loader) == ([{"id": 1}], False)
    assert cache.get_or_set("x", loader) == ([{"id": 1}], True)
    assert len(calls) == 1
    assert cache.hit_ratio == 0.5


def test_cache_outage_falls_back_to_source():
    class Broken:
        def get(self, k):
            raise ConnectionError("redis down")

        def set(self, k, v, ttl):
            raise ConnectionError("redis down")

    cache = CacheAside(Broken())
    value, hit = cache.get_or_set("x", lambda: [1, 2])
    assert value == [1, 2] and hit is False


@pytest.fixture
def client():
    data = [{"id": 1, "name": "Managed Compute"}]
    app = create_app(cache=CacheAside(MemoryBackend()), data_source=lambda: data)
    return app.test_client()


def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == 200 and r.json["status"] == "ok"


def test_services_cache_headers(client):
    first = client.get("/api/services")
    second = client.get("/api/services")
    assert first.headers["X-Cache"] == "MISS"
    assert second.headers["X-Cache"] == "HIT"
    assert second.json["count"] == 1
    assert "Server-Timing" in second.headers


def test_metrics_exposes_latency_histogram(client):
    client.get("/api/services")
    body = client.get("/metrics").data.decode()
    assert "http_request_duration_seconds_bucket" in body
    assert 'le="0.2"' in body
