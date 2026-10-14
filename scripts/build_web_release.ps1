param([string]$FlutterPath = 'C:\src\flutter\bin\flutter.bat')
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$releaseIdentifier = [Guid]::NewGuid().ToString('N')
Push-Location -LiteralPath $projectDirectory
try {
    $manifestPath = Join-Path $projectDirectory 'build\web\web-release.json'
    # Never let a previous manifest become an offline resource of this release.
    if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath }
    & $FlutterPath build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run --dart2js-optimization=O2 "--dart-define=WEB_RELEASE=$releaseIdentifier"
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar: nenhuma nova versão deve ser publicada.' }
    $manifest = @{ release = $releaseIdentifier; created = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json
    [System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
} finally {
    Pop-Location
}
