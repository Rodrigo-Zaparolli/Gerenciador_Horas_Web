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
    $manifest = @{ release = $releaseIdentifier; created = [DateTime]::UtcNow.ToString('o'); changes = @($releaseNotes.changes) } | ConvertTo-Json
    [System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
} finally {
    Pop-Location
}
