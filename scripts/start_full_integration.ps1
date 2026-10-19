param([switch]$Background)
$ErrorActionPreference = 'Stop'
$integrationDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$integrationPython = Join-Path $integrationDirectory 'python\python.exe'
$env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $integrationDirectory 'python\ms-playwright'
$env:EDESK_INTEGRATION_VERSION = 'comment-close-19'
$health = $null
try { $health = Invoke-RestMethod 'http://127.0.0.1:8765/healthz' -TimeoutSec 3 } catch { }
if ($health -and $health.service -eq 'gerenciador-horas-edesk') {
    if ($health.busy) { throw 'Aguarde o envio atual terminar antes de iniciar este pacote.' }
    if ($health.mode -eq 'central') { throw 'Existe uma integração central ativa neste PC. Encerre-a antes de iniciar este pacote local.' }
    if ($health.integrationPackageVersion -ne 'comment-close-19' -or $health.mode -ne 'local') {
        $listener = Get-NetTCPConnection -LocalPort 8765 -State Listen |
            Where-Object { $_.LocalAddress -eq '127.0.0.1' } | Select-Object -First 1
        if (-not $listener) { throw 'Não foi possível identificar a integração anterior.' }
        $previousProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)"
        if (-not $previousProcess.ExecutablePath -or
            (Split-Path $previousProcess.ExecutablePath -Leaf) -ne 'python.exe' -or
            $previousProcess.CommandLine -notmatch '-m\s+local_edesk\.(files_server|server)(?:\s|$)') {
            throw 'A conexão pertence a outro programa. Nenhum processo foi encerrado.'
        }
        $previousDirectory = [IO.Path]::GetFullPath((Split-Path (Split-Path $previousProcess.ExecutablePath -Parent) -Parent))
        if (-not (Test-Path -LiteralPath (Join-Path $previousDirectory 'local_edesk'))) {
            throw 'Não foi possível verificar a pasta da integração anterior.'
        }
        $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($previousProcess.ProcessId)" |
            Where-Object { $_.CommandLine -match 'edesk_(horas|fases|comentario|percentual)\.py' }
        if ($children) { throw 'Aguarde o envio E-Desk terminar antes de atualizar.' }
        Stop-Process -Id $previousProcess.ProcessId
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            if (-not (Get-Process -Id $previousProcess.ProcessId -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 250
        }
        # Keep already-authorized file references and send history on this PC.
        # SQLite backup also handles a WAL database without copying its files.
        foreach ($databaseName in @('local-files.sqlite3', 'history.sqlite3')) {
            $previousDatabase = Join-Path $previousDirectory ".edesk-local\$databaseName"
            $currentDatabase = Join-Path $integrationDirectory ".edesk-local\$databaseName"
            if ($databaseName -eq 'local-files.sqlite3' -and (Test-Path -LiteralPath $previousDatabase)) {
                & $integrationPython (Join-Path $PSScriptRoot 'migrate_integration_data.py') --file-links $previousDatabase
                if ($LASTEXITCODE -ne 0) { throw 'Não foi possível preservar os vínculos locais da integração anterior.' }
                continue
            }
            if ($previousDirectory -ne $integrationDirectory -and
                (Test-Path -LiteralPath $previousDatabase) -and
                -not (Test-Path -LiteralPath $currentDatabase)) {
                & $integrationPython (Join-Path $PSScriptRoot 'migrate_integration_data.py') $previousDatabase $currentDatabase
                if ($LASTEXITCODE -ne 0) { throw 'Não foi possível preservar os dados da integração anterior.' }
            }
        }
        Write-Host 'Integração anterior substituída. Sua pasta antiga foi preservada.'
    }
}
& (Join-Path $PSScriptRoot 'start_edesk_local.ps1')
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw 'Não foi possível iniciar a integração completa.' }
if (-not $Background) {
    & (Join-Path $PSScriptRoot 'integration_autostart.ps1')
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw 'Nao foi possivel ativar o inicio automatico.' }
    Start-Process 'https://gerenciador-horas.web.app/integracao-completa.html' -WindowStyle Hidden
}
