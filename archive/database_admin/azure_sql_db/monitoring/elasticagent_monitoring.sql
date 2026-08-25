/* =========================================================
   Elastic Jobs Observability Views (Compatible Version)
   Assumptions:
   - jobs.job_name exists
   - jobs.jobsteps exists
   - jobs.target_groups / target_group_members exist
   ========================================================= */

------------------------------------------------------------
-- 1. Execution History
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_execution_history AS
SELECT
    j.job_id,
    j.job_name,
    je.job_execution_id,
    je.lifecycle AS execution_status,
    je.current_attempts,
    je.create_time,
    je.start_time,
    je.end_time,
    DATEDIFF(SECOND, je.start_time, je.end_time) AS duration_sec,
    je.last_message
FROM jobs.job_executions je
JOIN jobs.jobs j
    ON j.job_id = je.job_id;
GO

------------------------------------------------------------
-- 2. Latest Job Status
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_latest_status AS
WITH latest AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY create_time DESC) rn
    FROM jobs.job_executions
)
SELECT
    j.job_id,
    j.job_name,
    l.job_execution_id,
    l.lifecycle AS execution_status,
    l.start_time,
    l.end_time,
    DATEDIFF(SECOND, l.start_time, l.end_time) AS duration_sec,
    l.last_message
FROM latest l
JOIN jobs.jobs j
    ON j.job_id = l.job_id
WHERE rn = 1;
GO

------------------------------------------------------------
-- 3. Currently Running Jobs
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_currently_running AS
SELECT
    j.job_name,
    je.job_execution_id,
    je.start_time,
    je.current_attempts
FROM jobs.job_executions je
JOIN jobs.jobs j
    ON j.job_id = je.job_id
WHERE je.lifecycle = 'InProgress';
GO

------------------------------------------------------------
-- 4. Failures
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_failures AS
SELECT
    j.job_name,
    je.job_execution_id,
    je.start_time,
    je.end_time,
    je.last_message
FROM jobs.job_executions je
JOIN jobs.jobs j
    ON j.job_id = je.job_id
WHERE je.lifecycle IN ('Failed', 'TimedOut');
GO

------------------------------------------------------------
-- 5. Long Running Jobs
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_long_running AS
SELECT
    j.job_name,
    je.job_execution_id,
    je.start_time,
    DATEDIFF(MINUTE, je.start_time, SYSUTCDATETIME()) AS running_minutes
FROM jobs.job_executions je
JOIN jobs.jobs j
    ON j.job_id = je.job_id
WHERE je.lifecycle = 'InProgress';
GO

------------------------------------------------------------
-- 6. Job → Step → Target Mapping
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_step_mapping AS
SELECT
    j.job_name,
    js.step_id,
    js.step_name,
    tg.target_group_name,
    tgm.target_type,
    tgm.server_name,
    tgm.database_name,
    tgm.elastic_pool_name
FROM jobs.jobs j
JOIN jobs.jobsteps js
    ON j.job_id = js.job_id
LEFT JOIN jobs.target_groups tg
    ON js.target_group_id = tg.target_group_id
LEFT JOIN jobs.target_group_members tgm
    ON tg.target_group_id = tgm.target_group_id;
GO

------------------------------------------------------------
-- 7. Execution with Target (Full Fan-out)
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_execution_with_target AS
SELECT
    j.job_name,
    je.job_execution_id,
    je.lifecycle AS execution_status,
    je.start_time,
    je.end_time,
    DATEDIFF(SECOND, je.start_time, je.end_time) AS duration_sec,
    js.step_name,
    tgm.target_type,
    tgm.server_name,
    tgm.database_name,
    tgm.elastic_pool_name,
    je.last_message
FROM jobs.job_executions je
JOIN jobs.jobs j
    ON j.job_id = je.job_id
LEFT JOIN jobs.jobsteps js
    ON j.job_id = js.job_id
LEFT JOIN jobs.target_groups tg
    ON js.target_group_id = tg.target_group_id
LEFT JOIN jobs.target_group_members tgm
    ON tg.target_group_id = tgm.target_group_id;
GO

------------------------------------------------------------
-- 8. Execution Expanded (Deduplicated per DB)
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_execution_expanded AS
SELECT DISTINCT
    j.job_name,
    je.job_execution_id,
    je.lifecycle AS execution_status,
    je.start_time,
    je.end_time,
    tgm.server_name,
    tgm.database_name
FROM jobs.job_executions je
JOIN jobs.jobs j
    ON j.job_id = je.job_id
LEFT JOIN jobs.jobsteps js
    ON j.job_id = js.job_id
LEFT JOIN jobs.target_group_members tgm
    ON js.target_group_id = tgm.target_group_id;
GO

------------------------------------------------------------
-- 9. SLA Breach (Adjust threshold as needed)
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_sla_breach AS
SELECT
    j.job_name,
    je.job_execution_id,
    je.start_time,
    je.end_time,
    DATEDIFF(MINUTE, je.start_time, je.end_time) AS duration_min,
    je.last_message
FROM jobs.job_executions je
JOIN jobs.jobs j
    ON j.job_id = je.job_id
WHERE je.lifecycle = 'Succeeded'
  AND DATEDIFF(MINUTE, je.start_time, je.end_time) > 10;
GO

------------------------------------------------------------
-- 10. Retry Analysis
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_retry_analysis AS
SELECT
    j.job_name,
    COUNT(*) AS total_runs,
    SUM(CASE WHEN je.current_attempts > 1 THEN 1 ELSE 0 END) AS retried_runs,
    MAX(je.current_attempts) AS max_attempts_seen
FROM jobs.job_executions je
JOIN jobs.jobs j
    ON j.job_id = je.job_id
GROUP BY j.job_name;
GO

------------------------------------------------------------
-- 11. Failure Trend
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_failure_trend AS
SELECT
    j.job_name,
    CAST(je.create_time AS DATE) AS run_date,
    COUNT(*) AS failure_count
FROM jobs.job_executions je
JOIN jobs.jobs j
    ON j.job_id = je.job_id
WHERE je.lifecycle IN ('Failed', 'TimedOut')
GROUP BY j.job_name, CAST(je.create_time AS DATE);
GO

------------------------------------------------------------
-- 12. Success Rate
------------------------------------------------------------
CREATE OR ALTER VIEW jobs.vw_job_success_rate AS
SELECT
    j.job_name,
    COUNT(*) AS total_runs,
    SUM(CASE WHEN je.lifecycle = 'Succeeded' THEN 1 ELSE 0 END) AS success_runs,
    CAST(
        100.0 * SUM(CASE WHEN je.lifecycle = 'Succeeded' THEN 1 ELSE 0 END)
        / COUNT(*) AS DECIMAL(5,2)
    ) AS success_rate_pct
FROM jobs.job_executions je
JOIN jobs.jobs j
    ON j.job_id = je.job_id
GROUP BY j.job_name;
GO