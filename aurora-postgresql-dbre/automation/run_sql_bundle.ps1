[CmdletBinding()]
param(
    [string]$PsqlPath = "psql"
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptRoot
$sqlDir = Join-Path $rootDir "sql\aurora_postgresql"

if (-not (Get-Command $PsqlPath -ErrorAction SilentlyContinue)) {
    throw "psql was not found. Provide -PsqlPath or install PostgreSQL client tools."
}

if (-not $env:DATABASE_URL -and -not $env:PGHOST) {
    throw "Set DATABASE_URL or standard PG* environment variables before running the bundle."
}

Get-ChildItem -Path $sqlDir -Filter *.sql |
    Sort-Object Name |
    ForEach-Object {
        Write-Host "Running $($_.Name)"
        & $PsqlPath "-v" "ON_ERROR_STOP=1" "-f" $_.FullName
        if (-not $?) {
            throw "Execution failed for $($_.FullName)"
        }
    }
