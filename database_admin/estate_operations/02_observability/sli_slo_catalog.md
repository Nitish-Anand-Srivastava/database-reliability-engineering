# SLI/SLO Catalog

## Golden signals
- Availability (% uptime)
- Query latency (p50/p95/p99)
- Throughput (TPS/QPS)
- Saturation (CPU, IOPS, connections, lock waits)
- Error budget burn

## SLO templates
- Tier 0 OLTP: 99.99% availability, p95 < 50ms
- Tier 1 OLTP: 99.95% availability, p95 < 120ms
- Tier 2 analytics: 99.9% availability, p95 < 2s
