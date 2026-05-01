<#
Performance baseline runner for SQL Server -> Azure SQL Hyperscale migration
Author: Nitish Anand Srivastava
#>

param(
    [Parameter(Mandatory = $true)][string]$SourceServer,
    [Parameter(Mandatory = $true)][string]$TargetServer,
    [Parameter(Mandatory = $true)][string]$Database,
    [Parameter(Mandatory = $true)][string]$QueryFile,
    [Parameter(Mandatory = $false)][string]$OutputFile = 'logs/performance_comparison.csv'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $QueryFile)) {
    throw "Query file not found: $QueryFile"
}

$queries = Get-Content -Path $QueryFile -Raw -Encoding UTF8
$queryBatches = $queries -split "(?m)^GO\s*$" | Where-Object { $_.Trim().Length -gt 0 }

$resultRows = @()

foreach ($q in $queryBatches) {
    $qName = ($q.Trim().Split("`n")[0]).Trim()
    if ($qName.Length -gt 80) { $qName = $qName.Substring(0, 80) }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    sqlcmd -S $SourceServer -d $Database -E -Q $q | Out-Null
    $sw.Stop()
    $sourceMs = $sw.ElapsedMilliseconds

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    sqlcmd -S $TargetServer -d $Database -G -Q $q | Out-Null
    $sw.Stop()
    $targetMs = $sw.ElapsedMilliseconds

    $deltaPct = 0.0
    if ($sourceMs -gt 0) {
        $deltaPct = (($targetMs - $sourceMs) / [double]$sourceMs) * 100.0
    }

    $resultRows += [PSCustomObject]@{
        query_name = $qName
        source_ms = $sourceMs
        target_ms = $targetMs
        delta_pct = [Math]::Round($deltaPct, 2)
    }
}

$resultRows | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
Write-Host "Performance comparison written to $OutputFile" -ForegroundColor Green
