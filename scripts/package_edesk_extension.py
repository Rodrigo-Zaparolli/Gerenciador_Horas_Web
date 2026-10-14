"""Package ONLY extension sources, never profiles, credentials or app data."""
from pathlib import Path
import json
import zipfile

root = Path(__file__).resolve().parents[1]
source = root / 'browser_extension'
files = ['manifest.json', 'background.js', 'bridge.js', 'core.js',
         'page-dom.js', 'runner.html', 'runner.css', 'runner.js']
manifest = json.loads((source / 'manifest.json').read_text(encoding='utf-8'))
assert manifest['manifest_version'] == 3
target = root / 'web/downloads/edesk-extensao.zip'
target.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as package:
    for name in files:
        package.write(source / name, name)
print(f'EXTENSION_PACKAGE_OK {len(files)} files')
