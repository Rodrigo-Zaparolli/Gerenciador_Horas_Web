param(
    [switch]$Disable,
    [string]$IntegrationDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$StartupDirectory = [Environment]::GetFolderPath('Startup')
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($StartupDirectory)) { throw 'Pasta de inicializacao do Windows indisponivel.' }
$startupPath = [IO.Path]::GetFullPath($StartupDirectory)
$shortcutPath = Join-Path $startupPath 'Gerenciador Horas - Integracao E-Desk.lnk'
if ($Disable) {
    if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) { Remove-Item -LiteralPath $shortcutPath }
    Write-Host 'Inicio automatico desativado. A integracao atual continua funcionando ate ser encerrada.'
    exit 0
}
$integrationPath = [IO.Path]::GetFullPath($IntegrationDirectory)
$backgroundScript = Join-Path $integrationPath 'scripts\start_integration_background.ps1'
if (-not (Test-Path -LiteralPath $backgroundScript -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $integrationPath 'scripts\start_full_integration.ps1') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $integrationPath 'python\python.exe') -PathType Leaf)) {
    throw 'Extraia o pacote completo para uma pasta permanente antes de ativar o inicio automatico.'
}
New-Item -ItemType Directory -Path $startupPath -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shortcut.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $backgroundScript + '"'
$shortcut.WorkingDirectory = $integrationPath
$shortcut.WindowStyle = 7
$shortcut.Description = 'Inicia a integracao E-Desk em segundo plano ao entrar no Windows.'
$shortcut.Save()
Write-Host 'Inicio automatico ativado para este usuario do Windows.'
