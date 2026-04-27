param(
    [Parameter(Mandatory = $true)]
    [string]$Engine,

    [Parameter(Mandatory = $true)]
    [string]$EngineRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$retentionDays = 7
$configFile = Join-Path $EngineRoot 'config/default.env'
if (Test-Path $configFile) {
    Get-Content $configFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#') -or -not $line.Contains('=')) { return }
        $parts = $line.Split('=', 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($key -eq 'RETENTION_DAYS' -and $value -match '^[0-9]+$') {
            $retentionDays = [int]$value
        }
    }
}

$snapshotPath = Join-Path $EngineRoot 'data/snapshots'
$reportPath = Join-Path $EngineRoot 'data/reports'
$logPath = Join-Path $EngineRoot 'logs'

$snapshotPath, $reportPath, $logPath | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}

$cutoff = (Get-Date).AddDays(-$retentionDays)
Get-ChildItem $snapshotPath -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force
Get-ChildItem $reportPath -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force
Get-ChildItem $logPath -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force

Write-Output "Retention cleanup complete for $Engine. Kept last $retentionDays days."
