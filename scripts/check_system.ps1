param(
    [string]$Flutter = 'C:\src\flutter\bin\flutter.bat',
    [switch]$Browser
)
# Read-only/simulated checks: never submits records to the real E-Desk.
$ErrorActionPreference = 'Stop'
$auditRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$auditPython = Join-Path $auditRoot 'python\python.exe'
if (-not (Test-Path -LiteralPath $auditPython)) { throw 'Python da integracao nao encontrado.' }
$auditOutput = Join-Path $auditRoot ('build\system-check-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $auditOutput -Force | Out-Null
$auditChecks = @(
    @{ Name = 'analyze'; Command = $Flutter; Arguments = @('analyze', '--no-pub') },
    @{ Name = 'flutter'; Command = $Flutter; Arguments = @('test', '--no-pub') },
    @{ Name = 'python'; Command = $auditPython; Arguments = @('-m', 'unittest', 'discover', '-s', 'test', '-p', 'test_*.py') },
    @{ Name = 'javascript'; Command = 'node'; Arguments = @('--test', 'test/edesk_extension_core_test.mjs') }
)
if ($Browser) {
    foreach ($auditFixture in @('hours_cold_start', 'hours_batch_flow', 'comment_close_flow', 'comment_percentage_flow', 'browser_local_files')) {
        $auditChecks += @{ Name = $auditFixture; Command = $auditPython; Arguments = @("scripts/check_$auditFixture.py") }
    }
}
$auditResults = @()
Push-Location -LiteralPath $auditRoot
try {
    foreach ($auditCheck in $auditChecks) {
        Write-Host "Checking $($auditCheck.Name)..."
        $auditLog = Join-Path $auditOutput ($auditCheck.Name + '.txt')
        $auditCommand = $auditCheck.Command
        $auditArguments = $auditCheck.Arguments
        $auditStarted = Get-Date
        $auditExit = 1
        try {
            Get-Command -Name $auditCommand -ErrorAction Stop | Out-Null
            # unittest normally writes progress to stderr on Windows.
            $ErrorActionPreference = 'Continue'
            & $auditCommand @auditArguments *> $auditLog
            $auditExit = $LASTEXITCODE
        } catch {
            $_ | Out-File -LiteralPath $auditLog -Append
        } finally {
            $ErrorActionPreference = 'Stop'
        }
        $auditResults += [pscustomobject]@{
            Check = $auditCheck.Name; ExitCode = $auditExit
            Seconds = [math]::Round(((Get-Date) - $auditStarted).TotalSeconds, 1)
            Log = $auditLog
        }
        Write-Host "$($auditCheck.Name): exit $auditExit"
    }
    $auditResults | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $auditOutput 'results.json') -Encoding UTF8
    $auditFailed = @($auditResults | Where-Object { $_.ExitCode -ne 0 })
    Write-Host "Results: $auditOutput"
    if ($auditFailed.Count) { throw "$($auditFailed.Count) check(s) failed. Inspect results.json and logs." }
    Write-Host 'SYSTEM_CHECK_OK - automated checks; real E-Desk acceptance remains separate.'
} finally {
    Pop-Location
}
