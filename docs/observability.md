# Observability for X-Road

Combine X-Road's **native monitoring** with a standard metrics/logs/alerts stack. Do not reinvent what the
platform already exposes.

## What X-Road already gives you

| Source | What it provides | How to read it |
|---|---|---|
| **Operational Monitoring** daemon | Per-service request counts, durations, success/failure, message sizes | Query metaservice; scrape into Prometheus |
| **Environmental Monitoring** | Certificate expiry, OS, installed packages, running processes, free disk | Query metaservice; alert on cert expiry |
| **Message log** | ASiC-E containers, signed + timestamped (non-repudiation) | Audit, disk usage, archiving |
| **Audit log** (`spec-al`) | Security-relevant events (config changes, logins) | Ship to log store, alert on anomalies |
| Proxy **health check** | Liveness for HA/load balancers | TCP/HTTP probe |
| Logback logs (`/var/log/xroad/`) | Component logs | Ship to Loki/ELK |

## Recommended stack (Grafana-centred)

- **Metrics:** Prometheus, scraping `node-exporter` (host), `cAdvisor` (containers), `postgres-exporter`
  (each ministry DB plus `serverconf`/`messagelog`), and a `jmx_exporter` sidecar on each Security Server
  (X-Road components use Dropwizard Metrics over JMX).
- **Dashboards:** Grafana.
- **Logs:** Loki + Promtail (or EFK/ELK with Filebeat). Ship `/var/log/xroad/*` and the audit log.
- **Alerting:** Grafana alerting or Alertmanager.
- **Correlation/tracing:** index logs by `X-Road-Request-Id` to join consumer and provider sides of one
  exchange. For full traces, add OpenTelemetry at the information-system layer (X-Road core does not emit OTel).

## Signals to alert on (X-Road-specific golden signals)

- **Certificate expiry** (authentication + signing certs): warn at 30 / 14 / 7 days. From environmental monitoring.
- **OCSP** responder reachability and validation failures (fail-closed events).
- **Global configuration freshness**: confclient last-download age. Expired global conf = outage.
- **Timestamping**: batch time-stamping success and message-log backlog.
- **Message log disk usage** and archiving lag.
- **Per-service** request rate, error rate (failure %), latency p50/p95/p99. From operational monitoring.
- **JVM** heap/GC and **DB** connection saturation per component.
- **Federation**: partner Central Server / global-conf reachability (if federated).

## SLOs to define

Provider service availability and latency targets per service; consumer success rate through the portal;
anchor/global-conf freshness budget. Tie alert thresholds to these, not to raw resource use.

## Sandbox overlay

A ready overlay (Prometheus + Grafana + Loki + Promtail + cAdvisor + node-exporter) sits in
`examples/timor-leste/observability/`. Run it alongside the sandbox:

```bash
cd examples/timor-leste
docker compose -f docker-compose.yml -f observability/docker-compose.observability.yml up -d
# Grafana http://localhost:3001  ·  Prometheus http://localhost:9090
```

JMX and postgres exporters are included as commented targets; enable them once the Security Servers expose JMX
and you point the exporter at each ministry database.

## Sources

- Operational monitoring: https://github.com/nordic-institute/X-Road/tree/develop/doc/OperationalMonitoring
- Environmental monitoring: https://github.com/nordic-institute/X-Road/tree/develop/doc/EnvironmentalMonitoring
- Audit log events (`spec-al`): https://github.com/nordic-institute/X-Road/blob/develop/doc/Architecture/spec-al_x-road_audit_log_events.md
