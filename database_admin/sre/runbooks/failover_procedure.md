# Failover Procedure

## Trigger Conditions
- Primary node failure
- Replication lag exceeds threshold

## Steps
1. Promote replica
2. Redirect application traffic
3. Validate writes on new primary

## Post-Failover
- Rebuild failed node as replica
