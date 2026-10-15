$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporary = [IO.Path]::GetFullPath((Join-Path $workspace ('build\autostart-test-' + [Guid]::NewGuid().ToString('N'))))
$expectedPrefix = $workspace.TrimEnd('\') + '\'
if (-not $temporary.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test path outside workspace.' }
$previousLocalData = $env:LOCALAPPDATA
try {
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    $startup = Join-Path $temporary 'Startup de teste'
    New-Item -ItemType Directory -Path $startup -Force | Out-Null
    $unrelated = Join-Path $startup 'outro-programa.txt'
    'keep' | Set-Content -LiteralPath $unrelated
    $manager = Join-Path $PSScriptRoot 'integration_autostart.ps1'
    $shell = New-Object -ComObject WScript.Shell
    foreach ($name in @('pacote inicial', 'nova pasta & teste')) {
        $fixture = Join-Path $temporary $name
        New-Item -ItemType Directory -Path (Join-Path $fixture 'scripts'), (Join-Path $fixture 'python') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $fixture 'python\python.exe') | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start_integration_background.ps1') -Destination (Join-Path $fixture 'scripts')
        Copy-Item -LiteralPath $manager -Destination (Join-Path $fixture 'scripts')
        @'
param([switch]$Background)
if (-not $Background) { throw 'Background mode required.' }
'BACKGROUND_START_OK'
'@ | Set-Content -LiteralPath (Join-Path $fixture 'scripts\start_full_integration.ps1')
        & (Join-Path $fixture 'scripts\integration_autostart.ps1') -StartupDirectory $startup
        & $manager -IntegrationDirectory $fixture -StartupDirectory $startup
        $links = @(Get-ChildItem -LiteralPath $startup -Filter '*.lnk')
        if ($links.Count -ne 1) { throw 'Duplicate startup shortcuts.' }
        $link = $shell.CreateShortcut($links[0].FullName)
        if ($link.WorkingDirectory -ne $fixture -or
            $link.Arguments -notlike '*-WindowStyle Hidden*' -or
            $link.Arguments -notlike '*-NoProfile*' -or
            -not $link.Arguments.EndsWith('"' + (Join-Path $fixture 'scripts\start_integration_background.ps1') + '"')) {
            throw 'Startup shortcut lost its current package path or hidden launch mode.'
        }
    }
    $env:LOCALAPPDATA = Join-Path $temporary 'perfil de teste'
    $wrapper = Join-Path $fixture 'scripts\start_integration_background.ps1'
    $powerShellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $wrapper + '"'
    $process = Start-Process -FilePath $powerShellPath -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    $logPath = Join-Path $env:LOCALAPPDATA 'GerenciadorHoras\integracao\logs\startup.log'
    if ($process.ExitCode -ne 0 -or (Get-Content -LiteralPath $logPath -Raw) -notmatch 'BACKGROUND_START_OK') {
        throw 'Background launch failed.'
    }
    "throw 'TEST_FAILURE'" | Set-Content -LiteralPath (Join-Path $fixture 'scripts\start_full_integration.ps1')
    $process = Start-Process -FilePath $powerShellPath -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 1 -or (Get-Content -LiteralPath $logPath -Raw) -notmatch 'TEST_FAILURE') {
        throw 'Background failure was not recorded.'
    }
    & $manager -Disable -StartupDirectory $startup
    & $manager -Disable -StartupDirectory $startup
    if (@(Get-ChildItem -LiteralPath $startup -Filter '*.lnk').Count -ne 0 -or
        -not (Test-Path -LiteralPath $unrelated)) { throw 'Disable removed unrelated startup data.' }
    'AUTOSTART_OK: idempotent enable, package relocation, hidden launch, log, failure handling, reversible disable'
} finally {
    $env:LOCALAPPDATA = $previousLocalData
    $resolvedTemporary = [IO.Path]::GetFullPath($temporary)
    if (-not $resolvedTemporary.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup.' }
    if (Test-Path -LiteralPath $resolvedTemporary) { Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force }
}
