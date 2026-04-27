param()
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$engineRoot = Resolve-Path (Join-Path $scriptDir '..')
& (Join-Path $scriptDir '..\..\common\cleanup_retention_engine.ps1') -Engine 'oracle' -EngineRoot $engineRoot
