$ErrorActionPreference = 'Stop'
$projectDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pythonExecutable = Join-Path $projectDirectory 'python\python.exe'
$logDirectory = Join-Path $projectDirectory 'build\edesk-local'
if (-not (Test-Path -LiteralPath $pythonExecutable)) {
    throw 'Python não encontrado na pasta do aplicativo.'
}
function Get-IntegrationStatus {
    try { Invoke-RestMethod -Uri 'http://127.0.0.1:8765/healthz' -TimeoutSec 2 }
    catch { $null }
}
$status = Get-IntegrationStatus
if ($status -and $status.service -eq 'gerenciador-horas-edesk' -and $status.mode -in @('local', 'central')) {
    if ($status.nativeFiles -and $status.excelMirror -and $status.nativeFilesVersion -eq 'persistent-file-links-7' -and $status.nativeProjectLinkRecovery -eq $true) {
        Write-Host 'A integração já está ativa. Pode abrir as pastas e planilhas originais pelo site.'
        exit 0
    }
    if ($status.busy) { throw 'Aguarde o envio E-Desk terminar antes de atualizar a abertura local.' }
    & (Join-Path $PSScriptRoot 'stop_edesk_local.ps1')
}
& $pythonExecutable -c "import flask, google.auth, cachecontrol, waitress"
if ($LASTEXITCODE -ne 0) { throw 'Execute scripts\install_edesk_local.ps1 antes de iniciar.' }
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$process = Start-Process -FilePath $pythonExecutable -ArgumentList '-m','local_edesk.server' `
    -WorkingDirectory $projectDirectory -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $logDirectory 'service.log') `
    -RedirectStandardError (Join-Path $logDirectory 'service-error.log')
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 500
    $status = Get-IntegrationStatus
    if ($status -and $status.service -eq 'gerenciador-horas-edesk' -and $status.mode -eq 'local' -and $status.nativeProjectLinkRecovery -eq $true) {
        $process.Id | Set-Content -LiteralPath (Join-Path $logDirectory 'service.pid')
        Write-Host 'Integração E-Desk ativa. Abra https://gerenciador-horas.web.app neste computador.'
        exit 0
    }
    if ($process.HasExited) { break }
}
throw "Não foi possível iniciar a integração. Consulte os registros em $logDirectory."
