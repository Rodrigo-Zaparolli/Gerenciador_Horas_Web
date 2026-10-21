"""Verify Docker's source bundle in isolation, without Docker or live requests."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ContainerSourcesTest(unittest.TestCase):
    def test_source_bundle_imports_bots_and_starts_protected_api(self):
        docker = (ROOT / 'Dockerfile').read_text(encoding='utf-8')
        ignore = (ROOT / '.dockerignore').read_text(encoding='utf-8').splitlines()
        requirements = (ROOT / 'cloud_run/requirements.txt').read_text(encoding='utf-8')
        self.assertIn('firebase-admin==', requirements)
        required = ['edesk_bot/comment_percentage.py', 'edesk_bot/send_progress.py',
                    'edesk_bot/work_selection.py', 'edesk_bot/hour_receipt.py',
                    'edesk_bot/edesk_percentual.py',
                    'edesk_bot/phase_confirmation.py', 'local_edesk/__init__.py',
                    'local_edesk/central.py', 'local_edesk/journal.py']
        for source in required:
            self.assertIn('!' + source, ignore)
            self.assertIn('COPY ' + source + ' /app/' + source, docker)
        (ROOT / 'build').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='container-sources-', dir=ROOT / 'build') as directory:
            target = Path(directory)
            for source, destination in re.findall(r'^COPY\s+(\S+)\s+(/app/\S+)\s*$', docker, re.M):
                incoming = ROOT / source
                outgoing = target / destination.removeprefix('/app/')
                self.assertTrue(outgoing.resolve().is_relative_to(target.resolve()))
                outgoing.parent.mkdir(parents=True, exist_ok=True)
                if incoming.is_dir():
                    shutil.copytree(incoming, outgoing, ignore=shutil.ignore_patterns('__pycache__'))
                else:
                    shutil.copy2(incoming, outgoing)
            program = '''
import os, sys, types
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root))
sys.path.insert(0, str(root / 'edesk_bot'))
os.environ['EDESK_LOCAL_MODE'] = 'false'
os.environ['EDESK_CENTRAL_MODE'] = 'false'
os.environ['EDESK_DATA_DIR'] = str(root / 'runtime')
# Docker installs Firebase Admin; model it here without credentials or network.
firebase_admin = types.ModuleType('firebase_admin')
firebase_admin.initialize_app = lambda *args, **kwargs: None
firebase_admin.auth = types.ModuleType('firebase_admin.auth')
sys.modules['firebase_admin'] = firebase_admin
sys.modules['firebase_admin.auth'] = firebase_admin.auth
import edesk_horas, edesk_fases, edesk_comentario, edesk_percentual
from cloud_run.main import app
with app.test_client() as client:
    health = client.get('/healthz')
    assert health.status_code == 200
    assert health.json['mode'] == 'cloud'
    assert health.json['nativeFiles'] is False
    assert client.post('/api/edesk/horas', json={}).status_code == 401
print('CONTAINER_SOURCE_IMPORTS_AND_PROTECTED_API_OK')
'''
            result = subprocess.run([sys.executable, '-I', '-c', program, str(target)],
                                    capture_output=True, text=True, timeout=30,
                                    env=os.environ.copy())
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('CONTAINER_SOURCE_IMPORTS_AND_PROTECTED_API_OK', result.stdout)


if __name__ == '__main__':
    unittest.main()
