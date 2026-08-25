# Runbook Template

Use this template for any operational runbook (incident response, failover, recovery, maintenance).

## 1) Summary

- Runbook ID:
- Service/Platform:
- Severity Scope:
- Owner:
- Last Reviewed:
- Next Review Date:

## 2) Impact and Reliability Context

- Business impact if unresolved:
- User-facing symptoms:
- SLO affected:
- Error budget policy:
- RTO/RPO constraints (if applicable):

## 3) Preconditions and Risk Gates

- Access prerequisites (IAM/RBAC/break-glass):
- Change window requirements:
- Required approvals:
- Safety stop conditions:

## 4) Preparation Checklist

- [ ] Confirm incident/change ticket ID
- [ ] Confirm stakeholder bridge channel
- [ ] Validate backup/restore readiness
- [ ] Snapshot key metrics baseline
- [ ] Confirm rollback path and dependencies

## 5) Procedure

Document each step with explicit decision points.

### Step 1

- Goal:
- Commands/Actions:
- Expected result:
- If result differs:

### Step 2

- Goal:
- Commands/Actions:
- Expected result:
- If result differs:

## 6) Verification

- Technical checks:
- Data integrity checks:
- Performance checks:
- Application health checks:
- Success criteria:

## 7) Rollback

- Rollback trigger conditions:
- Rollback steps:
- Validation after rollback:
- Escalation criteria if rollback fails:

## 8) Communication

- Required updates (who, when):
- Incident bridge update cadence:
- External/customer communication requirements:

## 9) Evidence and Audit Trail

- Ticket/Change IDs:
- Query/command logs:
- Dashboards/screenshots:
- Timeline (UTC):
- Final incident summary link:

## 10) Automation Opportunities

- Candidate tasks for automation:
- Proposed automation owner:
- Risk of automation:
- Validation plan for automation:

## 11) Lessons Learned

- What worked well:
- What failed:
- Action items with owners and due dates:
