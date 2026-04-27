param(
    [Parameter(Mandatory = $true)]
    [string]$Engine,

    [Parameter(Mandatory = $true)]
    [string]$EngineRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$configFile = Join-Path $EngineRoot 'config/default.env'
$snapshotSql = Join-Path $EngineRoot 'snapshots/snapshot_queries.sql'
$reportBuilder = Join-Path $PSScriptRoot 'report_builder_stub.py'
$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')

$snapshotDir = Join-Path $EngineRoot 'data/snapshots'
$reportDir = Join-Path $EngineRoot 'data/reports'
$logDir = Join-Path $EngineRoot 'logs'
$logFile = Join-Path $logDir 'cpf.log'
$snapshotOut = Join-Path $snapshotDir ("snapshot_{0}.txt" -f $timestamp)
$reportTxt = Join-Path $reportDir ("report_{0}.txt" -f $timestamp)
$reportHtml = Join-Path $reportDir ("report_{0}.html" -f $timestamp)

$snapshotDir, $reportDir, $logDir | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format s) $Message"
    Add-Content -Path $logFile -Value $line
    Write-Output $Message
}

function Load-Config {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#') -or -not $line.Contains('=')) { return }
        $parts = $line.Split('=', 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
}

function Add-Section {
    param(
        [string]$Title,
        [scriptblock]$Body
    )

    Add-Content -Path $reportTxt -Value ""
    Add-Content -Path $reportTxt -Value ("## {0}" -f $Title)
    Add-Content -Path $reportTxt -Value ""

    try {
        $output = & $Body 2>&1 | Out-String
        Add-Content -Path $reportTxt -Value $output
    }
    catch {
        Add-Content -Path $reportTxt -Value 'Section unavailable on this server/version or insufficient privileges.'
        Add-Content -Path $reportTxt -Value ""
        Add-Content -Path $logFile -Value ("{0} {1}" -f (Get-Date -Format s), $_.Exception.Message)
    }
}

function Build-Header {
    param([string]$Target)

    @(
        'CPF Observability AWR-Style Detailed Performance Report',
        "Engine: $Engine",
        "Generated (UTC): $timestamp",
        "Host context: $Target",
        '',
        'Sections marked unavailable indicate missing permissions, feature flags, or version differences.'
    ) | Set-Content -Path $reportTxt
}

Load-Config -Path $configFile

$dbHost = [System.Environment]::GetEnvironmentVariable('DB_HOST', 'Process')
if (-not $dbHost) { $dbHost = '127.0.0.1' }
$dbPort = [System.Environment]::GetEnvironmentVariable('DB_PORT', 'Process')
$dbUser = [System.Environment]::GetEnvironmentVariable('DB_USER', 'Process')
$dbName = [System.Environment]::GetEnvironmentVariable('DB_NAME', 'Process')
$dbPassword = [System.Environment]::GetEnvironmentVariable('DB_PASSWORD', 'Process')

if (-not $dbPort) {
    switch ($Engine) {
        'postgresql' { $dbPort = '5432' }
        'aurora_postgresql' { $dbPort = '5432' }
        'mysql' { $dbPort = '3306' }
        'aurora_mysql' { $dbPort = '3306' }
        'aws_rds' { $dbPort = '3306' }
        'sqlserver' { $dbPort = '1433' }
        'azure_sql_db' { $dbPort = '1433' }
        'oracle' { $dbPort = '1521' }
        'redis' { $dbPort = '6379' }
        'clickhouse' { $dbPort = '9000' }
        'cassandra' { $dbPort = '9042' }
        default { $dbPort = '' }
    }
}

$target = if ($dbName) { "$dbUser@$dbHost`:$dbPort/$dbName" } else { "$dbHost`:$dbPort" }
if (-not $dbUser) { $target = "$dbHost`:$dbPort" }
Build-Header -Target $target

Write-Log "Running one-off snapshot at $timestamp"
Write-Log "Target: $target"

switch ($Engine) {
    'mysql' { 
        $dbUser = if ($dbUser) { $dbUser } else { 'root' }
        $dbName = if ($dbName) { $dbName } else { 'performance_schema' }

        Add-Section 'Instance Identity and Version' { mysql -h $dbHost -P $dbPort -u $dbUser -D $dbName --table -e "SELECT NOW() AS collected_at_utc, @@hostname AS hostname, @@port AS port, @@version AS version, @@version_comment AS flavor, @@read_only AS read_only" }
        Add-Section 'Uptime and Connection Pressure' { mysql -h $dbHost -P $dbPort -u $dbUser -D $dbName --table -e "SHOW GLOBAL STATUS WHERE Variable_name IN ('Uptime','Threads_running','Threads_connected','Max_used_connections','Connections','Aborted_connects','Connection_errors_max_connections')" }
        Add-Section 'Top SQL by Total Time' { mysql -h $dbHost -P $dbPort -u $dbUser -D $dbName --table -e "SELECT DIGEST, LEFT(DIGEST_TEXT, 160) AS sql_text, COUNT_STAR AS exec_count, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_s, ROUND(AVG_TIMER_WAIT/1000000000,3) AS avg_ms, SUM_ROWS_EXAMINED AS rows_examined, SUM_NO_INDEX_USED AS no_index_used FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_TIMER_WAIT DESC LIMIT 20" }
        Add-Section 'Blocking Chains' { mysql -h $dbHost -P $dbPort -u $dbUser -D $dbName --table -e "SELECT r.trx_id AS waiting_trx_id, b.trx_id AS blocking_trx_id, TIMESTAMPDIFF(SECOND, r.trx_started, NOW()) AS waiting_seconds, LEFT(r.trx_query, 200) AS waiting_query, LEFT(b.trx_query, 200) AS blocking_query FROM information_schema.innodb_lock_waits w JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id ORDER BY waiting_seconds DESC LIMIT 20" }
    }
    'aurora_mysql' { 
        & $PSCommandPath -Engine 'mysql' -EngineRoot $EngineRoot
        exit $LASTEXITCODE
    }
    'aws_rds' {
        & $PSCommandPath -Engine 'mysql' -EngineRoot $EngineRoot
        exit $LASTEXITCODE
    }
    'postgresql' {
        $dbUser = if ($dbUser) { $dbUser } else { 'postgres' }
        $dbName = if ($dbName) { $dbName } else { 'postgres' }
        if ($dbPassword) { $env:PGPASSWORD = $dbPassword }

        Add-Section 'Instance Identity and Version' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT now() AS collected_at_utc, inet_server_addr() AS server_ip, inet_server_port() AS server_port, version();" }
        Add-Section 'Connection Pressure' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS max_connections, (SELECT count(*) FROM pg_stat_activity) AS current_connections, (SELECT count(*) FROM pg_stat_activity WHERE state='active') AS active_connections;" }
        Add-Section 'Top SQL by Total Time' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT queryid, calls, ROUND(total_exec_time::numeric,2) AS total_ms, ROUND(mean_exec_time::numeric,2) AS mean_ms, rows, left(query, 180) AS query FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 20;" }
        Add-Section 'Blocking Chains' { psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT blocked.pid AS blocked_pid, blocker.pid AS blocker_pid, blocked.usename AS blocked_user, blocker.usename AS blocker_user, now() - blocked.query_start AS blocked_for, left(blocked.query, 160) AS blocked_query, left(blocker.query, 160) AS blocker_query FROM pg_stat_activity blocked JOIN pg_stat_activity blocker ON blocker.pid = ANY(pg_blocking_pids(blocked.pid)) ORDER BY blocked_for DESC LIMIT 20;" }
    }
    'aurora_postgresql' {
        & $PSCommandPath -Engine 'postgresql' -EngineRoot $EngineRoot
        exit $LASTEXITCODE
    }
    'sqlserver' {
        $dbName = if ($dbName) { $dbName } else { 'master' }
        $server = "$dbHost,$dbPort"
        Add-Section 'Instance Identity and Version' { sqlcmd -S $server -d $dbName -W -Q "SELECT GETUTCDATE() AS collected_at_utc, @@SERVERNAME AS server_name, @@VERSION AS version;" }
        Add-Section 'Top Waits' { sqlcmd -S $server -d $dbName -W -Q "SELECT TOP 25 wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms FROM sys.dm_os_wait_stats ORDER BY wait_time_ms DESC;" }
        Add-Section 'Top CPU Queries' { sqlcmd -S $server -d $dbName -W -Q "SELECT TOP 20 qs.execution_count, qs.total_worker_time/1000 AS total_cpu_ms, qs.total_elapsed_time/1000 AS total_elapsed_ms, qs.total_logical_reads, LEFT(st.text,240) AS sql_text FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st ORDER BY qs.total_worker_time DESC;" }
        Add-Section 'Blocking Sessions' { sqlcmd -S $server -d $dbName -W -Q "SELECT TOP 25 r.session_id, r.blocking_session_id, r.wait_type, r.wait_time, r.cpu_time, r.logical_reads, LEFT(t.text,240) AS sql_text FROM sys.dm_exec_requests r OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t WHERE r.blocking_session_id <> 0 ORDER BY r.wait_time DESC;" }
    }
    'azure_sql_db' {
        & $PSCommandPath -Engine 'sqlserver' -EngineRoot $EngineRoot
        exit $LASTEXITCODE
    }
    default {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if ($bash) {
            $linuxRunner = Join-Path $PSScriptRoot 'run_oneoff_engine.sh'
            & $bash.Source $linuxRunner $Engine $EngineRoot
            exit $LASTEXITCODE
        }

        Add-Section 'Engine Support Notice' { "Windows native deep sections are currently implemented for mysql/postgresql/sqlserver families. Install bash (Git Bash/WSL) for full cross-engine detail on Windows." }
    }
}

if (Test-Path $snapshotSql) {
    try {
        Add-Content -Path $snapshotOut -Value (Get-Content $snapshotSql -Raw)
    }
    catch {
        Add-Content -Path $snapshotOut -Value 'Snapshot SQL exists but could not be read.'
    }
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    python $reportBuilder --engine $Engine --input $reportTxt --output $reportHtml | Out-Null
}
elseif (Get-Command py -ErrorAction SilentlyContinue) {
    py $reportBuilder --engine $Engine --input $reportTxt --output $reportHtml | Out-Null
}
else {
    $escaped = (Get-Content $reportTxt -Raw)
    $escaped = $escaped.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    "<html><head><meta charset='utf-8'><title>$Engine report</title></head><body><pre>$escaped</pre></body></html>" | Set-Content -Path $reportHtml
}

Write-Log "Snapshot written: $snapshotOut"
Write-Log "Detailed TXT report: $reportTxt"
Write-Log "Detailed HTML report: $reportHtml"
