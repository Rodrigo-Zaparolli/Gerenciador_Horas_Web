"""Validate the extracted portable runtime without opening user files."""
import json
import os
import subprocess
import tempfile
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
validation_root = (root / 'build').resolve()
validation_root.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='opener-validation-', dir=validation_root) as directory:
    extracted = Path(directory).resolve()
    assert extracted.is_relative_to(validation_root)
    with zipfile.ZipFile(root / 'web/downloads/abertura-local-windows.zip') as archive:
        for item in archive.infolist():
            target = (extracted / item.filename).resolve()
            assert target.is_relative_to(extracted)
            assert not any(part in {'perfil', '.edesk-local', 'ms-playwright'} for part in Path(item.filename).parts)
        archive.extractall(extracted)
    environment = {key: value for key, value in os.environ.items() if key not in {'PYTHONPATH','PYTHONHOME'}}
    code = '''
import sys,json,tkinter
sys.path.insert(0,sys.argv[1])
from local_edesk.files_server import app
import pythoncom, win32clipboard
from PIL import Image
from local_edesk.excel_mirror import render
from unittest.mock import patch
client=app.test_client()
health=client.get('/healthz')
assert health.status_code==200 and health.json['nativeFiles'] is True
assert health.json['excelMirror'] is True
assert 'preview' in health.json['nativeActions']
assert health.json['nativeFilesVersion'] == 'full-path-links-3'
headers={'Origin':'https://gerenciador-horas.web.app','Authorization':'Bearer invalid-test-token'}
with patch('local_edesk.files_server.verify_token',side_effect=ValueError):
    assert client.post('/api/local-files',json={'action':'open'},headers=headers).status_code==401
assert client.post('/api/local-files',json={'action':'open'}).status_code==403
assert client.post('/api/local-files',json={},headers=headers,environ_overrides={'REMOTE_ADDR':'192.168.1.2'}).status_code==403
assert client.post('/api/local-files',json={},headers={**headers,'Origin':'https://evil.invalid'}).status_code==403
with patch('local_edesk.files_server.verify_token',return_value={'sub':'test-user'}),patch('local_edesk.files_server.execute',return_value={'opened':True}) as opened:
    assert client.post('/api/local-files',json={'action':'open','reference':'test'},headers=headers).status_code==200
    opened.assert_called_once_with('test-user',{'action':'open','reference':'test'})
gui=tkinter.Tk();gui.withdraw();gui.update();gui.destroy()
print(json.dumps({'portable_runtime':'ok','native_dialog_dependencies':'ok','user_auth':'required','loopback_only':'ok','app_origin_only':'ok'}))
'''
    result = subprocess.run([str(extracted/'python/python.exe'), '-I', '-c', code, str(extracted)],
        cwd=extracted, env=environment, text=True, capture_output=True, timeout=45)
    if result.returncode:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())
    assert extracted.is_relative_to(validation_root)
