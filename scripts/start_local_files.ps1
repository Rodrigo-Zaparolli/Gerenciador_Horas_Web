$ErrorActionPreference = 'Stop'
$openerDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$openerPython = Join-Path $openerDirectory 'python\python.exe'
function Get-OpenerStatus {
    try { Invoke-RestMethod 'http://127.0.0.1:8765/healthz' -TimeoutSec 2 } catch { $null }
}
$status = Get-OpenerStatus
if ($status) {
    if ($status.service -eq 'gerenciador-horas-edesk' -and $status.nativeFiles -and $status.excelMirror -and $status.nativeFilesVersion -eq 'persistent-file-links-7') {
        Write-Host 'Abertura local já está ativa. Pode usar o aplicativo web.'
        exit 0
    }
    if ($status.service -eq 'gerenciador-horas-edesk' -and $status.mode -eq 'files-only') {
        # A previous extraction may still own the port and have a different PID file.
        $listener = Get-NetTCPConnection -LocalPort 8765 -State Listen |
            Where-Object { $_.LocalAddress -eq '127.0.0.1' } | Select-Object -First 1
        if (-not $listener) { throw 'Não foi possível identificar a integração anterior.' }
        $previousProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)"
        if (-not $previousProcess.ExecutablePath -or
            (Split-Path $previousProcess.ExecutablePath -Leaf) -ne 'python.exe' -or
            $previousProcess.CommandLine -notmatch '-m\s+local_edesk\.files_server(?:\s|$)') {
            throw 'A conexão pertence a outro programa. Nenhum processo foi encerrado.'
        }
        $previousDirectory = [IO.Path]::GetFullPath((Split-Path (Split-Path $previousProcess.ExecutablePath -Parent) -Parent))
        $previousDatabase = Join-Path $previousDirectory '.edesk-local\local-files.sqlite3'
        & (Join-Path $PSScriptRoot 'stop_local_files.ps1')
        for ($stopAttempt = 0; $stopAttempt -lt 10; $stopAttempt++) {
            $status = Get-OpenerStatus
            if (-not $status) { break }
            Start-Sleep -Milliseconds 500
        }
        if (-not $status -and (Test-Path -LiteralPath $previousDatabase)) {
            & $openerPython (Join-Path $PSScriptRoot 'migrate_integration_data.py') --file-links $previousDatabase
            if ($LASTEXITCODE -ne 0) { throw 'Não foi possível preservar os vínculos locais anteriores.' }
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
    if ($status.service -eq 'gerenciador-horas-edesk' -and $status.nativeFiles -and $status.excelMirror -and $status.nativeFilesVersion -eq 'persistent-file-links-7') {
        $openerProcess.Id | Set-Content -LiteralPath (Join-Path $openerLog 'service.pid')
        Write-Host 'Abertura local ativa. Você pode fechar esta janela.'
        Start-Process 'https://gerenciador-horas.web.app/abrir-arquivos.html' -WindowStyle Hidden
        exit 0
    }
    if ($openerProcess.HasExited) { break }
}
throw 'Não foi possível iniciar. Consulte build\local-files\service-error.log na pasta extraída.'
