param(
        [switch]$Install
)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runScript = Join-Path $scriptDir 'run_oneoff.ps1'
$cleanupScript = Join-Path $scriptDir 'cleanup_retention.ps1'

Write-Output "Recommended Windows schedule for postgresql:"
Write-Output "- Every 30 minutes: powershell -ExecutionPolicy Bypass -File `"$runScript`""
Write-Output "- Daily at 01:15: powershell -ExecutionPolicy Bypass -File `"$cleanupScript`""

if ($Install) {
        $action1 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -File `"$runScript`""
        $trigger1 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30)
        Register-ScheduledTask -TaskName "CPF-postgresql-OneOff" -Action $action1 -Trigger $trigger1 -Description "CPF one-off report every 30 minutes" -Force | Out-Null

        $action2 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -File `"$cleanupScript`""
        $trigger2 = New-ScheduledTaskTrigger -Daily -At 1:15AM
        Register-ScheduledTask -TaskName "CPF-postgresql-Cleanup" -Action $action2 -Trigger $trigger2 -Description "CPF retention cleanup" -Force | Out-Null
        Write-Output "Scheduled tasks installed."
}
