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
digest = hashlib.sha256(compiled).hexdigest()
print(f'LOCAL_RELEASE_OK: {release} SHA256={digest}')
if args.public:
    import requests
    base = 'https://gerenciador-horas.web.app/'
    with requests.Session() as session:
        response = session.get(base + 'web-release.json', params={'check': time.time_ns()}, timeout=30)
        response.raise_for_status()
        assert response.json()['release'] == release, 'Public manifest differs'
        response = session.get(base + 'main.dart.js', params={'check': time.time_ns()}, timeout=120)
        response.raise_for_status()
        assert hashlib.sha256(response.content).hexdigest() == digest, 'Public compiled application differs'
        response = session.get(base, params={'check': time.time_ns()}, timeout=30)
        response.raise_for_status()
        assert 'flutter_bootstrap.js?release=' in response.text
    print('PUBLIC_RELEASE_OK: manifest, compiled application and loader match')
