$ErrorActionPreference = 'Stop'
$projectDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pidFile = Join-Path $projectDirectory 'build\edesk-local\service.pid'
if (-not (Test-Path -LiteralPath $pidFile)) { Write-Host 'A integração não está ativa.'; exit 0 }
$serviceProcessId = [int](Get-Content -LiteralPath $pidFile)
$process = Get-CimInstance Win32_Process -Filter "ProcessId=$serviceProcessId"
if ($process -and $process.CommandLine -match '-m\s+local_edesk\.server' -and
    $process.ExecutablePath -eq (Join-Path $projectDirectory 'python\python.exe')) {
    $integrationStatus = $null
    try { $integrationStatus = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/healthz' -TimeoutSec 2 } catch { }
    if ($integrationStatus -and $integrationStatus.service -eq 'gerenciador-horas-edesk' -and $integrationStatus.busy) {
        throw 'Uma operação E-Desk está em andamento. Aguarde sua conclusão antes de encerrar a integração.'
    }
    $runningAutomation = Get-CimInstance Win32_Process -Filter "ParentProcessId=$serviceProcessId" |
        Where-Object { $_.CommandLine -match 'edesk_(horas|fases|comentario|percentual)\.py' }
    if ($runningAutomation) {
        throw 'Uma operação E-Desk está em andamento. Aguarde sua conclusão antes de encerrar a integração.'
    }
    Stop-Process -Id $serviceProcessId
    Write-Host 'Integração E-Desk encerrada.'
} elseif ($process) { throw 'O processo registrado não pertence à integração. Nenhum processo foi encerrado.' }
Remove-Item -LiteralPath $pidFile
