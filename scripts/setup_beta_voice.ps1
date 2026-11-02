$ErrorActionPreference = 'Stop'
$betaAppRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$betaRuntime = Join-Path $betaAppRoot '.edesk-local\beta-voice'
$betaPython = Join-Path $betaAppRoot 'python\python.exe'
if (-not (Test-Path -LiteralPath $betaPython)) { throw 'Python da integração não encontrado. Use o pacote completo.' }
New-Item -ItemType Directory -Path $betaRuntime -Force | Out-Null
& $betaPython -m pip --version *> $null
if ($LASTEXITCODE -ne 0) {
    & $betaPython -m ensurepip --upgrade
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível preparar o instalador Python. Use o pacote completo v60.' }
}
& $betaPython -m pip install --target (Join-Path $betaRuntime 'vendor') 'kokoro-onnx==0.4.7' 'soundfile==0.14.0' 'vosk==0.3.45'
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível preparar as dependências de voz.' }
foreach ($betaAsset in @('kokoro-v1.0.onnx','voices-v1.0.bin')) {
    $betaTarget = Join-Path $betaRuntime $betaAsset
    if (-not (Test-Path -LiteralPath $betaTarget)) {
        Invoke-WebRequest -Uri "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/$betaAsset" -OutFile "$betaTarget.download"
        Move-Item -LiteralPath "$betaTarget.download" -Destination $betaTarget
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $betaRuntime 'vosk-model-small-pt-0.3\final.mdl'))) {
    $betaArchive = Join-Path $betaRuntime 'portugues.zip'
    Invoke-WebRequest -Uri 'https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip' -OutFile $betaArchive
    Expand-Archive -LiteralPath $betaArchive -DestinationPath $betaRuntime -Force
}
Write-Host 'Voz Dora e reconhecimento local preparados. Reinicie a integração quando não houver operações em andamento.'
