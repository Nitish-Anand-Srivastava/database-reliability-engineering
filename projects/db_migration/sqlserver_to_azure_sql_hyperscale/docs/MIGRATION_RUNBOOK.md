# Migration Runbook: SQL Server to Azure SQL Database Hyperscale

## Scope

This runbook executes a 12-week enterprise migration for a large on-prem SQL Server database to Azure SQL Database Hyperscale.

---

## Phase 0: Preconditions

1. Confirm source backup and restore drills are passing
2. Confirm Azure subscription, networking, and target Hyperscale provisioning
3. Confirm migration scope tables and exclusion list approved
4. Confirm application freeze and cutover window approved

Exit criteria:
- Governance approvals complete
- Access and credentials validated
- Rollback playbook approved

---

## Phase 1: Bulk Seed (Weeks 1-4)

## Step 1: Assessment and remediation

1. Run schema assessment scripts
2. Document unsupported constructs and remediation actions
3. Generate target deployment scripts
4. Deploy schema and security principals to target

Command examples:

```powershell
sqlcmd -S ONPREM-SQL01 -d SalesDB -E -i scripts/schema_assessment.sql -o logs/schema_assessment.out
```

## Step 2: Initial seed preparation

1. Create striped backups to Azure Blob URLs
2. Validate backup integrity and restore metadata
3. Launch seed orchestration script

```powershell
powershell -ExecutionPolicy Bypass -File scripts/bulk_seed_orchestration.ps1 \
  -SourceServer ONPREM-SQL01 \
  -SourceDatabase SalesDB \
  -StorageAccount migrationstaging01
```

## Step 3: Seed execution and verification

1. Execute DMS/full load pipeline
2. Track table-level completion
3. Run initial reconciliation checks

```powershell
sqlcmd -S hyperscale-prod.database.windows.net -d SalesDB -U mig_user -P <password> -i scripts/reconciliation_checks.sql -o logs/seed_recon.out
```

Exit criteria:
- Full seed completed
- No blocker defects in initial validation

---

## Phase 2: Continuous Sync (Weeks 3-10)

## Step 4: Enable delta capture

1. Enable CDC for in-scope source tables
2. Record starting LSN watermark
3. Start extractor and replay workers

```powershell
python scripts/sqlserver_cdc_extractor.py --mode start
python scripts/azure_sql_replay_worker.py --mode start
```

## Step 5: Operate and tune sync

1. Monitor lag dashboards every 15 minutes
2. Scale replay workers for high churn tables
3. Resolve dead-letter events daily

Operational SLOs:
- Delta lag under 5 minutes
- Replay error rate below 0.1%

Exit criteria:
- Stable sync achieved for at least 10 business days

---

## Phase 3: Validation and Cutover (Weeks 11-12)

## Step 6: Final validation cycle

1. Run full reconciliation scripts
2. Run business parity query set
3. Run performance baseline comparison

```powershell
sqlcmd -S hyperscale-prod.database.windows.net -d SalesDB -U mig_user -P <password> -i scripts/reconciliation_checks.sql -o logs/final_recon.out
sqlcmd -S hyperscale-prod.database.windows.net -d SalesDB -U mig_user -P <password> -i scripts/business_validation.sql -o logs/business_validation.out
powershell -ExecutionPolicy Bypass -File scripts/performance_baseline.ps1
```

## Step 7: Cutover execution

1. Announce freeze start
2. Quiesce source writes
3. Drain final delta queue
4. Validate zero-lag checkpoint
5. Switch connection endpoints
6. Execute smoke tests

Exit criteria:
- Application fully operational on Hyperscale
- No Sev-1 or Sev-2 defects

---

## Rollback Procedure

1. Trigger rollback if critical acceptance tests fail
2. Repoint applications to source SQL Server
3. Re-enable source write workload
4. Capture incident timeline and delta impact window
5. Open post-incident corrective action workstream

Rollback guardrail:
- 72-hour hypercare rollback window from cutover time

---

## Sign-off Matrix

- DBA Lead
- Application Owner
- Platform/SRE Lead
- Security/Compliance Lead
- Change Management Approver

---

## Evidence Artifacts

- Schema assessment report
- Seed completion report
- CDC lag trend report
- Final reconciliation report
- Performance comparison report
- Cutover execution checklist

---

Last Updated: 2026-05-01
