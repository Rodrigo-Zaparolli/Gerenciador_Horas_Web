param([string]$FlutterPath = 'C:\src\flutter\bin\flutter.bat')
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$releaseIdentifier = [Guid]::NewGuid().ToString('N')
$notesPath = Join-Path $projectDirectory 'release-notes.json'
$releaseNotes = Get-Content -LiteralPath $notesPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($releaseNotes.changes).Count -eq 0) { throw 'Informe as alterações da publicação em release-notes.json.' }
foreach ($note in $releaseNotes.changes) {
    if ($note -isnot [string] -or [string]::IsNullOrWhiteSpace($note)) { throw 'Cada alteração deve ser um texto preenchido.' }
}
Push-Location -LiteralPath $projectDirectory
try {
    $manifestPath = Join-Path $projectDirectory 'build\web\web-release.json'
    # Never let a previous manifest become an offline resource of this release.
    if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath }
    & $FlutterPath build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run --dart2js-optimization=O2 "--dart-define=WEB_RELEASE=$releaseIdentifier"
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar: nenhuma nova versão deve ser publicada.' }
    # A query parameter can still reuse an old installer in intermediary caches.
    # Put the package version in the actual filename used by the download page.
    $integrationStarter = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'start_full_integration.ps1') -Raw
    $integrationVersion = [regex]::Match($integrationStarter, "EDESK_INTEGRATION_VERSION\s*=\s*'[^']*-(\d+)'")
    if (-not $integrationVersion.Success) { throw 'Versao do pacote da integracao nao encontrada.' }
    $packageNumber = $integrationVersion.Groups[1].Value
    $downloadAliases = @{
        'integracao-edesk-completa-windows-v2.zip' = "integracao-edesk-completa-windows-v$packageNumber.zip"
        'abertura-local-windows.zip' = "abertura-local-windows-v$packageNumber.zip"
    }
    foreach ($sourceName in $downloadAliases.Keys) {
        $packageSource = Join-Path $projectDirectory "web\downloads\$sourceName"
        if (Test-Path -LiteralPath $packageSource) {
            Copy-Item -LiteralPath $packageSource -Destination (Join-Path $projectDirectory "build\web\downloads\$($downloadAliases[$sourceName])") -Force
        }
    }
    $manifest = @{ release = $releaseIdentifier; created = [DateTime]::UtcNow.ToString('o'); changes = @($releaseNotes.changes) } | ConvertTo-Json
    [System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
} finally {
    Pop-Location
}
