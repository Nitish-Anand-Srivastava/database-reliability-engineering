Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cpfRoot = Resolve-Path (Join-Path $scriptDir '..')

$engines = @(
    'oracle',
    'postgresql',
    'mysql',
    'sqlserver',
    'aurora_mysql',
    'aurora_postgresql',
    'aws_rds',
    'azure_sql_db',
    'cassandra',
    'clickhouse',
    'cosmosdb',
    'mongodb',
    'redis'
)

function Load-Config {
    param([string]$ConfigFile)

    if (-not (Test-Path $ConfigFile)) {
        return $false
    }

    Get-Content $ConfigFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#') -or -not $line.Contains('=')) {
            return
        }
        $parts = $line.Split('=', 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
    return $true
}

function Clear-ConfigVars {
    $keys = @(
        'DB_HOST','DB_PORT','DB_USER','DB_PASSWORD','DB_NAME','DB_SSL_MODE',
        'MYSQL_LOGIN_PATH','MYSQL_HOST','MYSQL_PORT','MYSQL_USER','MYSQL_DATABASE','MYSQL_PASSWORD',
        'PGHOST','PGPORT','PGUSER','PGDATABASE','PGPASSWORD',
        'SQLSERVER_HOST','SQLSERVER_PORT','SQLSERVER_USER','SQLSERVER_PASSWORD','SQLSERVER_DATABASE','SQLSERVER_TRUST_CERT',
        'ORACLE_CONNECT_STRING','ORACLE_USER','ORACLE_PASSWORD','ORACLE_HOST','ORACLE_PORT','ORACLE_SERVICE',
        'REDIS_HOST','REDIS_PORT','REDIS_PASSWORD',
        'MONGODB_URI',
        'CLICKHOUSE_HOST','CLICKHOUSE_PORT','CLICKHOUSE_USER','CLICKHOUSE_PASSWORD','CLICKHOUSE_DATABASE',
        'CASSANDRA_HOST','CASSANDRA_PORT','CASSANDRA_USER','CASSANDRA_PASSWORD','CASSANDRA_KEYSPACE',
        'COSMOS_SUBSCRIPTION','COSMOS_RESOURCE_GROUP','COSMOS_ACCOUNT'
    )
    foreach ($k in $keys) {
        [Environment]::SetEnvironmentVariable($k, $null, 'Process')
    }
}

function Tools-ForEngine {
    param([string]$Engine)

    switch ($Engine) {
        { $_ -in @('mysql','aurora_mysql','aws_rds') } { return @('mysql') }
        { $_ -in @('postgresql','aurora_postgresql') } { return @('psql') }
        { $_ -in @('sqlserver','azure_sql_db') } { return @('sqlcmd') }
        'oracle' { return @('sqlplus') }
        'redis' { return @('redis-cli') }
        'mongodb' { return @('mongosh') }
        'clickhouse' { return @('clickhouse-client') }
        'cassandra' { return @('cqlsh','nodetool') }
        'cosmosdb' { return @('az') }
        default { return @() }
    }
}

function Test-Connectivity {
    param([string]$Engine)

    try {
        switch ($Engine) {
            { $_ -in @('mysql','aurora_mysql','aws_rds') } {
                $host = if ($env:DB_HOST) { $env:DB_HOST } elseif ($env:MYSQL_HOST) { $env:MYSQL_HOST } else { '127.0.0.1' }
                $port = if ($env:DB_PORT) { $env:DB_PORT } elseif ($env:MYSQL_PORT) { $env:MYSQL_PORT } else { '3306' }
                $user = if ($env:DB_USER) { $env:DB_USER } elseif ($env:MYSQL_USER) { $env:MYSQL_USER } else { 'root' }
                $db = if ($env:DB_NAME) { $env:DB_NAME } elseif ($env:MYSQL_DATABASE) { $env:MYSQL_DATABASE } else { 'performance_schema' }
                if ($env:MYSQL_LOGIN_PATH) {
                    & mysql --connect-timeout=5 --login-path=$env:MYSQL_LOGIN_PATH -e "SELECT 1" | Out-Null
                }
                else {
                    & mysql --connect-timeout=5 --host=$host --port=$port --user=$user --database=$db -e "SELECT 1" | Out-Null
                }
                return $true
            }
            { $_ -in @('postgresql','aurora_postgresql') } {
                $host = if ($env:DB_HOST) { $env:DB_HOST } elseif ($env:PGHOST) { $env:PGHOST } else { '127.0.0.1' }
                $port = if ($env:DB_PORT) { $env:DB_PORT } elseif ($env:PGPORT) { $env:PGPORT } else { '5432' }
                $user = if ($env:DB_USER) { $env:DB_USER } elseif ($env:PGUSER) { $env:PGUSER } else { 'postgres' }
                $db = if ($env:DB_NAME) { $env:DB_NAME } elseif ($env:PGDATABASE) { $env:PGDATABASE } else { 'postgres' }
                if ($env:DB_PASSWORD) { $env:PGPASSWORD = $env:DB_PASSWORD }
                elseif ($env:PGPASSWORD) { $env:PGPASSWORD = $env:PGPASSWORD }
                & psql -X -h $host -p $port -U $user -d $db -c "SELECT 1" | Out-Null
                return $true
            }
            { $_ -in @('sqlserver','azure_sql_db') } {
                $host = if ($env:DB_HOST) { $env:DB_HOST } elseif ($env:SQLSERVER_HOST) { $env:SQLSERVER_HOST } else { '127.0.0.1' }
                $port = if ($env:DB_PORT) { $env:DB_PORT } elseif ($env:SQLSERVER_PORT) { $env:SQLSERVER_PORT } else { '1433' }
                $db = if ($env:DB_NAME) { $env:DB_NAME } elseif ($env:SQLSERVER_DATABASE) { $env:SQLSERVER_DATABASE } else { 'master' }
                if ($env:DB_USER -and $env:DB_PASSWORD) {
                    & sqlcmd -S "$host,$port" -d $db -U $env:DB_USER -P $env:DB_PASSWORD -Q "SELECT 1" | Out-Null
                }
                else {
                    & sqlcmd -S "$host,$port" -d $db -E -Q "SELECT 1" | Out-Null
                }
                return $true
            }
            'oracle' {
                $conn = $env:ORACLE_CONNECT_STRING
                if (-not $conn) {
                    $host = if ($env:DB_HOST) { $env:DB_HOST } elseif ($env:ORACLE_HOST) { $env:ORACLE_HOST } else { '127.0.0.1' }
                    $port = if ($env:DB_PORT) { $env:DB_PORT } elseif ($env:ORACLE_PORT) { $env:ORACLE_PORT } else { '1521' }
                    $service = if ($env:DB_NAME) { $env:DB_NAME } elseif ($env:ORACLE_SERVICE) { $env:ORACLE_SERVICE } else { 'ORCLPDB1' }
                    $user = if ($env:DB_USER) { $env:DB_USER } elseif ($env:ORACLE_USER) { $env:ORACLE_USER } else { 'system' }
                    $pass = if ($env:DB_PASSWORD) { $env:DB_PASSWORD } elseif ($env:ORACLE_PASSWORD) { $env:ORACLE_PASSWORD } else { '' }
                    $conn = "$user/$pass@//$host`:$port/$service"
                }
                @("SELECT 1 FROM dual;", "EXIT") | & sqlplus -s $conn | Out-Null
                return $true
            }
            'redis' {
                $host = if ($env:DB_HOST) { $env:DB_HOST } elseif ($env:REDIS_HOST) { $env:REDIS_HOST } else { '127.0.0.1' }
                $port = if ($env:DB_PORT) { $env:DB_PORT } elseif ($env:REDIS_PORT) { $env:REDIS_PORT } else { '6379' }
                if ($env:DB_PASSWORD) {
                    $pong = (& redis-cli -h $host -p $port -a $env:DB_PASSWORD PING)
                }
                elseif ($env:REDIS_PASSWORD) {
                    $pong = (& redis-cli -h $host -p $port -a $env:REDIS_PASSWORD PING)
                }
                else {
                    $pong = (& redis-cli -h $host -p $port PING)
                }
                return ($pong -match 'PONG')
            }
            'mongodb' {
                $uri = if ($env:MONGODB_URI) { $env:MONGODB_URI } else { 'mongodb://127.0.0.1:27017/admin' }
                $out = & mongosh $uri --quiet --eval "db.runCommand({ ping: 1 }).ok"
                return ($out -match '1')
            }
            'clickhouse' {
                $host = if ($env:DB_HOST) { $env:DB_HOST } elseif ($env:CLICKHOUSE_HOST) { $env:CLICKHOUSE_HOST } else { '127.0.0.1' }
                $port = if ($env:DB_PORT) { $env:DB_PORT } elseif ($env:CLICKHOUSE_PORT) { $env:CLICKHOUSE_PORT } else { '9000' }
                $user = if ($env:DB_USER) { $env:DB_USER } elseif ($env:CLICKHOUSE_USER) { $env:CLICKHOUSE_USER } else { 'default' }
                $db = if ($env:DB_NAME) { $env:DB_NAME } elseif ($env:CLICKHOUSE_DATABASE) { $env:CLICKHOUSE_DATABASE } else { 'default' }
                & clickhouse-client --host $host --port $port --user $user --database $db --query "SELECT 1" | Out-Null
                return $true
            }
            'cassandra' {
                $host = if ($env:DB_HOST) { $env:DB_HOST } elseif ($env:CASSANDRA_HOST) { $env:CASSANDRA_HOST } else { '127.0.0.1' }
                $port = if ($env:DB_PORT) { $env:DB_PORT } elseif ($env:CASSANDRA_PORT) { $env:CASSANDRA_PORT } else { '9042' }
                & cqlsh $host $port -e "SELECT release_version FROM system.local;" | Out-Null
                return $true
            }
            'cosmosdb' {
                if (-not ($env:COSMOS_SUBSCRIPTION -and $env:COSMOS_RESOURCE_GROUP -and $env:COSMOS_ACCOUNT)) {
                    return $false
                }
                & az cosmosdb show --subscription $env:COSMOS_SUBSCRIPTION --resource-group $env:COSMOS_RESOURCE_GROUP --name $env:COSMOS_ACCOUNT --output none | Out-Null
                return $true
            }
            default { return $false }
        }
    }
    catch {
        return $false
    }
}

Write-Output ("{0,-18} {1,-8} {2,-11} {3,-13} {4,-8} {5}" -f 'ENGINE','TOOLS','CONFIG','CONNECTIVITY','READY','NOTES')
Write-Output ("{0,-18} {1,-8} {2,-11} {3,-13} {4,-8} {5}" -f '------','-----','------','------------','-----','-----')

$overallPass = $true
foreach ($engine in $engines) {
    Clear-ConfigVars

    $engineRoot = Join-Path $cpfRoot $engine
    $configFile = Join-Path $engineRoot 'config/default.env'
    $configOk = Load-Config -ConfigFile $configFile

    $tools = Tools-ForEngine -Engine $engine
    $missing = @()
    foreach ($t in $tools) {
        if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
            $missing += $t
        }
    }

    $toolsStatus = if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' }
    $configStatus = if ($configOk) { 'PASS' } else { 'FAIL' }

    $connStatus = 'SKIPPED'
    if ($toolsStatus -eq 'PASS' -and $configStatus -eq 'PASS') {
        $connStatus = if (Test-Connectivity -Engine $engine) { 'PASS' } else { 'FAIL' }
    }

    $ready = 'PASS'
    $notes = 'ready'
    if ($toolsStatus -ne 'PASS' -or $configStatus -ne 'PASS' -or ($connStatus -ne 'PASS' -and $connStatus -ne 'SKIPPED')) {
        $ready = 'FAIL'
        $overallPass = $false
        if ($missing.Count -gt 0) {
            $notes = "missing tools: $($missing -join ',')"
        }
        elseif ($configStatus -ne 'PASS') {
            $notes = 'missing config/default.env'
        }
        else {
            $notes = 'connectivity check failed'
        }
    }

    Write-Output ("{0,-18} {1,-8} {2,-11} {3,-13} {4,-8} {5}" -f $engine,$toolsStatus,$configStatus,$connStatus,$ready,$notes)
}

if ($overallPass) {
    Write-Output ""
    Write-Output 'Validation result: PASS (all engines ready)'
    exit 0
}

Write-Output ""
Write-Output 'Validation result: FAIL (one or more engines not ready)'
exit 2
