# TODO

## High priority

- [ ] **Backups** — implement automated backup strategy.
      Options: `pg_dump` via cron, or WAL-G / pgBackRest for point-in-time recovery (PITR).
      Store backups off-site (S3-compatible storage).

- [ ] **Metrics export** — add `postgres_exporter` and `pgbouncer_exporter` sidecars
      for Prometheus scraping. Wire into Grafana dashboards.
      Key metrics: connection saturation, query latency, cache hit ratio, replication lag.

## Medium priority

- [ ] **Alerts** — define alerting rules on top of exported metrics:
      disk usage >80%, connection pool exhaustion, long-running queries, autovacuum lag.

- [ ] **Secrets management** — migrate from plaintext `.env` to a secrets backend
      (HashiCorp Vault, AWS Secrets Manager, or Docker Secrets).
      Add automatic secret rotation for the database password.

- [ ] **PgBouncer healthcheck** — implement an external liveness probe since the
      hardened image has no shell. Options: a sidecar TCP probe or a custom
      `HEALTHCHECK` wrapper image.

## Low priority

- [ ] **High Availability** — add a streaming replica and automatic failover.
      Options: Patroni (etcd/consul), Repmgr, or a managed PG service.
      Current setup is a single point of failure.

- [ ] **CI/CD pipeline** — automate config validation and deployment:
      lint `postgresql.conf` / `pgbouncer.ini.template`, run `docker compose config`,
      deploy on merge to main.

- [ ] **Planned upgrade process** — document the procedure for updating
      PostgreSQL and PgBouncer versions (image pin → test → rollout).
