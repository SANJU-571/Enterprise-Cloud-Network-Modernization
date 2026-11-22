-- Service catalogue for the self-service portal
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE TABLE IF NOT EXISTS service_catalogue (
    id          SERIAL PRIMARY KEY,
    name        TEXT        NOT NULL UNIQUE,
    tier        TEXT        NOT NULL CHECK (tier IN ('bronze', 'silver', 'gold')),
    region      TEXT        NOT NULL DEFAULT 'ca-central-1',
    status      TEXT        NOT NULL DEFAULT 'active',
    owner_email TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Task 1.2: index the predicates used by the hot read path
CREATE INDEX IF NOT EXISTS idx_service_catalogue_status_name
    ON service_catalogue (status, name);

-- Top 10 slowest statements (used during the performance tuning sprint)
-- SELECT query, calls, mean_exec_time, total_exec_time
-- FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;

INSERT INTO service_catalogue (name, tier, region) VALUES
    ('Managed Compute',      'gold',   'ca-central-1'),
    ('Object Storage',       'silver', 'ca-central-1'),
    ('Managed PostgreSQL',   'gold',   'ca-central-1'),
    ('Site-to-Site VPN',     'silver', 'ca-central-1'),
    ('Backup & DR',          'gold',   'ca-west-1')
ON CONFLICT (name) DO NOTHING;
