# AWS RDS Engine-Agnostic Checks

## Daily
- Instance status, CPU, memory, storage free, connections.
- Backup job status and retention.
- Read replica lag and health.
- Parameter/option group drift.

## Weekly
- Restore test from latest snapshot.
- Capacity trend (storage/autoscaling).
- Slow query review and top waits.
- IAM auth, secret rotation, and network policy review.
