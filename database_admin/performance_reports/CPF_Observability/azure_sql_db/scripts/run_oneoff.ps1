param()
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$engineRoot = Resolve-Path (Join-Path $scriptDir '..')
& (Join-Path $scriptDir '..\..\common\run_oneoff_engine.ps1') -Engine 'azure_sql_db' -EngineRoot $engineRoot
