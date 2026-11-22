"""
Stratos Cloud self-service portal API (reference workload).

A deliberately small Flask service used to validate the platform:
  * /healthz           - ALB / HAProxy / Route 53 health check target
  * /api/services      - read-heavy endpoint served through a Redis
                         cache-aside layer (action plan task 2.2)
  * /metrics           - Prometheus metrics (request latency histogram
                         feeds the p95 <= 200 ms SLA rule)

Configuration comes from environment variables set by the EC2 user data.
"""

from __future__ import annotations

import json
import logging
import os
import time
from collections.abc import Callable
from typing import Any

from flask import Flask, Response, g, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from app.cache import CacheAside, build_cache

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}',
)
log = logging.getLogger("stratos-app")

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Request latency",
    ["service", "endpoint"],
    # Buckets clustered around the 200 ms SLA so p95 is accurate there
    buckets=(0.025, 0.05, 0.1, 0.15, 0.18, 0.2, 0.25, 0.5, 1.0, 2.5),
)
REQUEST_COUNT = Counter(
    "http_requests_total", "Requests", ["service", "endpoint", "status"]
)

SERVICE_NAME = "portal-api"


def create_app(cache: CacheAside | None = None, data_source: Callable[[], list] | None = None) -> Flask:
    app = Flask(__name__)
    app.config["CACHE"] = cache or build_cache()
    app.config["DATA_SOURCE"] = data_source or _load_services_from_db

    @app.before_request
    def _start_timer() -> None:
        g.start = time.perf_counter()

    @app.after_request
    def _record(resp: Response) -> Response:
        endpoint = request.url_rule.rule if request.url_rule else "unknown"
        if endpoint != "/metrics":
            elapsed = time.perf_counter() - g.get("start", time.perf_counter())
            REQUEST_LATENCY.labels(SERVICE_NAME, endpoint).observe(elapsed)
            REQUEST_COUNT.labels(SERVICE_NAME, endpoint, str(resp.status_code)).inc()
            resp.headers["Server-Timing"] = f"app;dur={elapsed * 1000:.1f}"
        return resp

    @app.get("/healthz")
    def healthz() -> tuple[Response, int]:
        return jsonify(status="ok", region=os.getenv("AWS_REGION", "unknown")), 200

    @app.get("/api/services")
    def list_services() -> Response:
        cache: CacheAside = app.config["CACHE"]
        services, hit = cache.get_or_set(
            "services:all", app.config["DATA_SOURCE"], ttl=int(os.getenv("CACHE_TTL", "60"))
        )
        resp = jsonify(services=services, count=len(services))
        resp.headers["X-Cache"] = "HIT" if hit else "MISS"
        return resp

    @app.get("/metrics")
    def metrics() -> Response:
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    @app.errorhandler(500)
    def _err(e: Any) -> tuple[Response, int]:
        log.exception("unhandled error")
        return jsonify(error="internal error"), 500

    return app


def _load_services_from_db() -> list[dict]:
    """Query the service catalogue from PostgreSQL (RDS)."""
    import psycopg  # imported lazily so tests do not need a DB driver

    dsn = _resolve_dsn()
    with psycopg.connect(dsn, connect_timeout=3) as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id, name, tier, region, status FROM service_catalogue "
            "WHERE status = 'active' ORDER BY name"
        )
        cols = [c.name for c in cur.description]
        return [dict(zip(cols, row, strict=False)) for row in cur.fetchall()]


def _resolve_dsn() -> str:
    """Build a DSN from the RDS-managed secret (Secrets Manager)."""
    if os.getenv("DATABASE_URL"):
        return os.environ["DATABASE_URL"]
    import boto3

    secret = boto3.client("secretsmanager").get_secret_value(SecretId=os.environ["DB_SECRET_ID"])
    creds = json.loads(secret["SecretString"])
    host = os.environ.get("DB_HOST", creds.get("host", "localhost"))
    return (
        f"host={host} port=5432 dbname=stratos user={creds['username']} "
        f"password={creds['password']} sslmode=require"
    )


app = create_app() if os.getenv("APP_ENV") else None
