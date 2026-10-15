$ErrorActionPreference = 'Stop'
$localData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
$logDirectory = Join-Path $localData 'GerenciadorHoras\integracao\logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logPath = Join-Path $logDirectory 'startup.log'
try {
    & (Join-Path $PSScriptRoot 'start_full_integration.ps1') -Background *> $logPath
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} catch {
    $_.Exception.Message | Out-File -LiteralPath $logPath -Append -Encoding UTF8
    exit 1
}
