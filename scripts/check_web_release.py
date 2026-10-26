"""Read-only verification of the web build and, optionally, public Hosting."""
import argparse
import hashlib
import json
import re
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--public', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent / 'build' / 'web'
manifest = json.loads((root / 'web-release.json').read_text(encoding='utf-8'))
release = manifest['release']
assert re.fullmatch(r'[0-9a-f]{32}', release)
compiled = (root / 'main.dart.js').read_bytes()
assert release.encode() in compiled, 'Manifest and compiled application differ'
assert 'web-release.json' not in (root / 'flutter_service_worker.js').read_text(encoding='utf-8')
assert 'flutter_bootstrap.js?release=' in (root / 'index.html').read_text(encoding='utf-8')
assert 'voice_recognition.js' not in (root / 'index.html').read_text(encoding='utf-8'), 'Voice must not start in this release'
digest = hashlib.sha256(compiled).hexdigest()
download_page = (root / 'integracao-completa.html').read_text(encoding='utf-8')
downloads = re.findall(r'href="(/downloads/[^"?]+\.zip)"', download_page)
for download in downloads:
    assert (root / download.lstrip('/')).is_file(), f'Advertised download missing: {download}'
integration = manifest.get('integration')
if integration is not None:
    assert re.fullmatch(r'[1-9][0-9]*', integration['version'])
    for field in ['updateUrl', 'completeUrl']:
        download = integration[field]
        assert re.fullmatch(r'/downloads/[A-Za-z0-9._-]+\.zip', download)
        assert download.endswith((f"-{integration['version']}.zip", f"-v{integration['version']}.zip"))
        assert (root / download.lstrip('/')).is_file(), f'Update-modal download missing: {download}'
print(f'LOCAL_RELEASE_OK: {release} SHA256={digest}')
if args.public:
    import requests
    base = 'https://gerenciador-horas.web.app/'
    with requests.Session() as session:
        response = session.get(base + 'web-release.json', params={'check': time.time_ns()}, timeout=30)
        response.raise_for_status()
        assert response.json()['release'] == release, 'Public manifest differs'
        assert response.json().get('integration') == integration, 'Public integration downloads differ'
        response = session.get(base + 'main.dart.js', params={'check': time.time_ns()}, timeout=120)
        response.raise_for_status()
        assert hashlib.sha256(response.content).hexdigest() == digest, 'Public compiled application differs'
        response = session.get(base, params={'check': time.time_ns()}, timeout=30)
        response.raise_for_status()
        assert 'flutter_bootstrap.js?release=' in response.text
        assert 'voice_recognition.js' not in response.text, 'Public page still starts voice'
    print('PUBLIC_RELEASE_OK: manifest, compiled application and loader match')
