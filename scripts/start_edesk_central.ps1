param([string]$CentralAddress)
$ErrorActionPreference = 'Stop'
$projectDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pythonExecutable = Join-Path $projectDirectory 'python\python.exe'
$logDirectory = Join-Path $projectDirectory 'build\edesk-local'

function Test-PrivateAddress([string]$value) {
    $parts = $value.Split('.')
    if ($parts.Count -ne 4) { return $false }
    foreach ($part in $parts) {
        $number = 0
        if (-not [int]::TryParse($part, [ref]$number) -or $number -lt 0 -or $number -gt 255) { return $false }
    }
    return ($parts[0] -eq '10' -or ($parts[0] -eq '192' -and $parts[1] -eq '168') -or
        ($parts[0] -eq '172' -and [int]$parts[1] -ge 16 -and [int]$parts[1] -le 31))
}

if (-not $CentralAddress) {
    $networkAddresses = @(Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } |
        ForEach-Object { $_.IPv4Address.IPAddress } | Where-Object { Test-PrivateAddress $_ })
    if ($networkAddresses.Count -ne 1) {
        throw 'Informe o IPv4 da rede: scripts\start_edesk_central.ps1 -CentralAddress 192.168.1.10'
    }
    $CentralAddress = $networkAddresses[0]
}
if (-not (Test-PrivateAddress $CentralAddress)) { throw 'Use um IPv4 da rede privada.' }
$adapter = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq $CentralAddress } | Select-Object -First 1
if (-not $adapter) { throw 'O endereço informado não pertence a este computador.' }
$profile = Get-NetConnectionProfile -InterfaceIndex $adapter.InterfaceIndex
if (-not $profile -or $profile.NetworkCategory -notin @('Private', 'DomainAuthenticated')) {
    throw 'A central exige uma rede Windows privada ou de domínio. Não compartilhe a integração em rede pública.'
}
if (-not (Test-Path -LiteralPath $pythonExecutable)) { throw 'Python não encontrado na pasta do aplicativo.' }
& $pythonExecutable -c 'import flask, google.auth, cachecontrol, waitress'
if ($LASTEXITCODE -ne 0) { throw 'Execute scripts\install_edesk_local.ps1 antes de iniciar.' }

$ruleName = 'GerenciadorHorasEdeskCentral'
$rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
if (-not $rule) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Na primeira execução, abra Iniciar central E-Desk.cmd como administrador para liberar a porta somente na rede privada.'
    }
    New-NetFirewallRule -Name $ruleName -DisplayName 'Gerenciador de Horas - central E-Desk' `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8765 `
        -RemoteAddress LocalSubnet -Profile Private,Domain -Program $pythonExecutable | Out-Null
}

$status = $null
try { $status = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/healthz' -TimeoutSec 2 } catch { }
if ($status -and $status.service -eq 'gerenciador-horas-edesk') {
    if ($status.mode -eq 'central') {
        Write-Host 'A central já está ativa. No app, abra Integração E-Desk > Configurar central.'
        exit 0
    }
    if (-not (Test-Path -LiteralPath (Join-Path $logDirectory 'service.pid'))) {
        throw 'A integração local ativa não tem registro do processo. Encerre-a antes de iniciar a central.'
    }
    & (Join-Path $PSScriptRoot 'stop_edesk_local.ps1')
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw 'Não foi possível encerrar a integração local.' }
    Start-Sleep -Milliseconds 500
}
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$previousMode = $env:EDESK_CENTRAL_MODE
$previousAddress = $env:EDESK_CENTRAL_HOST
try {
    $env:EDESK_CENTRAL_MODE = 'true'
    $env:EDESK_CENTRAL_HOST = $CentralAddress
    $process = Start-Process -FilePath $pythonExecutable -ArgumentList '-m','local_edesk.server' `
        -WorkingDirectory $projectDirectory -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $logDirectory 'service.log') `
        -RedirectStandardError (Join-Path $logDirectory 'service-error.log')
} finally {
    $env:EDESK_CENTRAL_MODE = $previousMode
    $env:EDESK_CENTRAL_HOST = $previousAddress
}
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 500
    try { $status = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/healthz' -TimeoutSec 2 } catch { $status = $null }
    if ($status -and $status.service -eq 'gerenciador-horas-edesk' -and $status.mode -eq 'central') {
        $process.Id | Set-Content -LiteralPath (Join-Path $logDirectory 'service.pid')
        Write-Host "Central ativa em http://${CentralAddress}:8765"
        Write-Host 'Abra o app neste PC: Integração E-Desk > Configurar central > Autorizar este PC como central.'
        Write-Host 'Os demais computadores da mesma conta e rede utilizarão a central pelo navegador.'
        exit 0
    }
    if ($process.HasExited) { break }
}
throw "Não foi possível iniciar a central. Consulte os registros em $logDirectory."
