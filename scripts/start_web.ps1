param(
    [ValidateRange(1024, 65535)][int]$Port = 8080,
    [switch]$Build,
    [switch]$Storage,
    [string]$EdeskApiUrl = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location -LiteralPath $projectRoot
try {
    if ($Build -or $Storage -or $EdeskApiUrl -or !(Test-Path -LiteralPath 'build/web/index.html')) {
        $buildArguments = @('build', 'web', '--release', '--no-web-resources-cdn', '--no-wasm-dry-run')
        if ($Storage) { $buildArguments += '--dart-define=PROJECT_STORAGE_ENABLED=true' }
        if ($EdeskApiUrl) { $buildArguments += "--dart-define=EDESK_API_URL=$EdeskApiUrl" }
        & flutter @buildArguments
        if ($LASTEXITCODE -ne 0) { throw 'A compilação web falhou.' }
    }
    $pythonExecutable = Join-Path $projectRoot 'python/python.exe'
    if (!(Test-Path -LiteralPath $pythonExecutable)) {
        $pythonExecutable = (Get-Command python -ErrorAction Stop).Source
    }
    Write-Host "Abra http://localhost:$Port no navegador. Use Ctrl+C para encerrar."
    & $pythonExecutable -m http.server $Port --bind 127.0.0.1 --directory (Join-Path $projectRoot 'build/web')
} finally {
    Pop-Location
}
