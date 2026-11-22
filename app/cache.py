"""
Cache-aside helper.

    value = cache.get(key)
    if value is None:
        value = db.query()
        cache.set(key, value, ttl)
    return value

Falls back to an in-process TTL cache when Redis is not configured (local dev,
tests) and degrades gracefully if Redis is unreachable: a cache outage must
never become an application outage.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from collections.abc import Callable
from typing import Any, Protocol

log = logging.getLogger("stratos-app.cache")


class Backend(Protocol):
    def get(self, key: str) -> str | None: ...
    def set(self, key: str, value: str, ttl: int) -> None: ...


class MemoryBackend:
    """Thread-safe in-process TTL store."""

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._data: dict[str, tuple[float, str]] = {}
        self._lock = threading.Lock()
        self._clock = clock

    def get(self, key: str) -> str | None:
        with self._lock:
            item = self._data.get(key)
            if item is None:
                return None
            expires, value = item
            if self._clock() >= expires:
                del self._data[key]
                return None
            return value

    def set(self, key: str, value: str, ttl: int) -> None:
        with self._lock:
            self._data[key] = (self._clock() + ttl, value)


class RedisBackend:
    def __init__(self, host: str, port: int = 6379, tls: bool = True) -> None:
        import redis

        self._r = redis.Redis(
            host=host,
            port=port,
            ssl=tls,
            socket_timeout=0.05,          # 50 ms: never let the cache blow the SLA
            socket_connect_timeout=0.1,
            health_check_interval=30,
        )

    def get(self, key: str) -> str | None:
        v = self._r.get(key)
        return v.decode() if v is not None else None

    def set(self, key: str, value: str, ttl: int) -> None:
        self._r.set(key, value, ex=ttl)


class CacheAside:
    def __init__(self, backend: Backend, prefix: str = "stratos:") -> None:
        self.backend = backend
        self.prefix = prefix
        self.hits = 0
        self.misses = 0

    def get_or_set(self, key: str, loader: Callable[[], Any], ttl: int = 60) -> tuple[Any, bool]:
        """Return (value, cache_hit)."""
        full_key = self.prefix + key
        try:
            cached = self.backend.get(full_key)
        except Exception as exc:  # cache down -> go straight to source
            log.warning("cache get failed: %s", exc)
            cached = None

        if cached is not None:
            self.hits += 1
            return json.loads(cached), True

        self.misses += 1
        value = loader()
        try:
            self.backend.set(full_key, json.dumps(value, default=str), ttl)
        except Exception as exc:
            log.warning("cache set failed: %s", exc)
        return value, False

    @property
    def hit_ratio(self) -> float:
        total = self.hits + self.misses
        return self.hits / total if total else 0.0


def build_cache() -> CacheAside:
    host = os.getenv("REDIS_HOST", "")
    if host:
        return CacheAside(RedisBackend(host, tls=os.getenv("REDIS_TLS", "true") == "true"))
    return CacheAside(MemoryBackend())
