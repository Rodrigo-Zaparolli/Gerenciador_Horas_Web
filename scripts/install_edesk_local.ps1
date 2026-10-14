$ErrorActionPreference = 'Stop'
$projectDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pythonExecutable = Join-Path $projectDirectory 'python\python.exe'
& $pythonExecutable -m pip install --disable-pip-version-check -r (Join-Path $projectDirectory 'local_edesk\requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível instalar os componentes da integração.' }
& $pythonExecutable -m playwright install chromium
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível instalar o navegador da integração.' }
Write-Host 'Instalação concluída. Utilize Iniciar integração E-Desk.cmd.'
