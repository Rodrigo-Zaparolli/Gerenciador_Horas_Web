$ErrorActionPreference = 'Stop'
$openerDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$openerPython = Join-Path $openerDirectory 'python\python.exe'
function Get-OpenerStatus {
    try { Invoke-RestMethod 'http://127.0.0.1:8765/healthz' -TimeoutSec 2 } catch { $null }
}
$status = Get-OpenerStatus
if ($status) {
    if ($status.service -eq 'gerenciador-horas-edesk' -and $status.nativeFiles -and $status.excelMirror -and $status.nativeFilesVersion -eq 'excel-preview-2') {
        Write-Host 'Abertura local já está ativa. Pode usar o aplicativo web.'
        exit 0
    }
    if ($status.service -eq 'gerenciador-horas-edesk' -and $status.mode -eq 'files-only') {
        # A previous extraction may still own the port and have a different PID file.
        & (Join-Path $PSScriptRoot 'stop_local_files.ps1')
        for ($stopAttempt = 0; $stopAttempt -lt 10; $stopAttempt++) {
            $status = Get-OpenerStatus
            if (-not $status) { break }
            Start-Sleep -Milliseconds 500
        }
    }
    if ($status) {
    throw 'A porta da integração já está ocupada. Atualize ou encerre a integração anterior antes de iniciar este pacote.'
    }
}
$openerLog = Join-Path $openerDirectory 'build\local-files'
New-Item -ItemType Directory -Path $openerLog -Force | Out-Null
$openerProcess = Start-Process -FilePath $openerPython -ArgumentList '-m','local_edesk.files_server' `
    -WorkingDirectory $openerDirectory -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $openerLog 'service.log') `
    -RedirectStandardError (Join-Path $openerLog 'service-error.log')
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 500
    $status = Get-OpenerStatus
    if ($status.service -eq 'gerenciador-horas-edesk' -and $status.nativeFiles -and $status.excelMirror -and $status.nativeFilesVersion -eq 'excel-preview-2') {
        $openerProcess.Id | Set-Content -LiteralPath (Join-Path $openerLog 'service.pid')
        Write-Host 'Abertura local ativa. Você pode fechar esta janela.'
        Start-Process 'https://gerenciador-horas.web.app/abrir-arquivos.html' -WindowStyle Hidden
        exit 0
    }
    if ($openerProcess.HasExited) { break }
}
throw 'Não foi possível iniciar. Consulte build\local-files\service-error.log na pasta extraída.'
