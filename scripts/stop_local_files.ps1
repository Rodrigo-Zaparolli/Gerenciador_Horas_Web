$ErrorActionPreference = 'Stop'
$openerDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$openerPidFile = Join-Path $openerDirectory 'build\local-files\service.pid'
if (Test-Path -LiteralPath $openerPidFile) {
    $openerProcessId = [int](Get-Content -LiteralPath $openerPidFile)
} else {
    $connection = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -eq '127.0.0.1' } | Select-Object -First 1
    if (-not $connection) { Write-Host 'Abertura local não está ativa.'; return }
    $openerProcessId = $connection.OwningProcess
}
$openerProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$openerProcessId"
$verifiedOpener = $false
if ($openerProcess -and $openerProcess.ExecutablePath -and
    $openerProcess.CommandLine -match '-m\s+local_edesk\.files_server(?:\s|$)') {
    $runningDirectory = Split-Path (Split-Path $openerProcess.ExecutablePath -Parent) -Parent
    $verifiedOpener = (Split-Path $openerProcess.ExecutablePath -Leaf) -eq 'python.exe' -and
        (Test-Path -LiteralPath (Join-Path $runningDirectory 'local_edesk\files_server.py'))
}
if ($verifiedOpener) {
    Stop-Process -Id $openerProcessId
    if (Test-Path -LiteralPath $openerPidFile) { Remove-Item -LiteralPath $openerPidFile }
    Write-Host 'Abertura local encerrada.'
} elseif ($openerProcess) { throw 'O processo não pertence a este pacote. Nenhum processo foi encerrado.' }
