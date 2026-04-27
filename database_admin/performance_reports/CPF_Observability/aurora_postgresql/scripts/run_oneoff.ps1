param()
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$engineRoot = Resolve-Path (Join-Path $scriptDir '..')
& (Join-Path $scriptDir '..\..\common\run_oneoff_engine.ps1') -Engine 'aurora_postgresql' -EngineRoot $engineRoot
