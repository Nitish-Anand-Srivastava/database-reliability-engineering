<#
Bulk seed orchestration for SQL Server to Azure SQL Hyperscale
Author: Nitish Anand Srivastava
#>

param(
    [Parameter(Mandatory = $true)][string]$SourceServer,
    [Parameter(Mandatory = $true)][string]$SourceDatabase,
    [Parameter(Mandatory = $true)][string]$StorageAccount,
    [Parameter(Mandatory = $false)][string]$StorageContainer = 'sql-seed',
    [Parameter(Mandatory = $false)][int]$StripeCount = 16
)

$ErrorActionPreference = 'Stop'

Write-Host "Starting bulk seed orchestration for $SourceDatabase from $SourceServer" -ForegroundColor Cyan

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupPrefix = "${SourceDatabase}_seed_${timestamp}"

# Build striped backup URL list
$backupUrls = @()
for ($i = 1; $i -le $StripeCount; $i++) {
    $backupUrls += "https://${StorageAccount}.blob.core.windows.net/${StorageContainer}/${backupPrefix}_part${i}.bak"
}

Write-Host "Generated $StripeCount backup stripe URLs" -ForegroundColor Yellow

# Render backup statement
$backupClauses = $backupUrls | ForEach-Object { "DISK = N'$_'" }
$backupTarget = ($backupClauses -join ",`n    ")

$backupSql = @"
BACKUP DATABASE [$SourceDatabase]
TO
    $backupTarget
WITH
    COPY_ONLY,
    COMPRESSION,
    CHECKSUM,
    STATS = 5;
"@

Write-Host "Executing backup on source SQL Server..." -ForegroundColor Cyan
sqlcmd -S $SourceServer -d master -E -Q $backupSql

if ($LASTEXITCODE -ne 0) {
    throw "Backup execution failed."
}

Write-Host "Backup completed successfully." -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Validate backup blobs exist and sizes are consistent." -ForegroundColor White
Write-Host "2. Start Azure DMS migration project for full load seed." -ForegroundColor White
Write-Host "3. Run reconciliation checks after load completion." -ForegroundColor White
