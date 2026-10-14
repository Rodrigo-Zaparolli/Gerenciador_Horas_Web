"""Smoke-test extracted runtime and APIs; never send data to E-Desk."""
import hashlib
import json
import os
import socket
import subprocess
import tempfile
import time
import zipfile
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'web/downloads/integracao-edesk-completa-windows-v2.zip'
VALIDATION = ROOT / 'build/full-integration-validation'
VALIDATION.mkdir(parents=True, exist_ok=True)

with zipfile.ZipFile(PACKAGE) as archive:
    for name in archive.namelist():
        path = Path(name)
        assert not path.is_absolute() and '..' not in path.parts
        assert path.parts[0] in {'python', 'edesk_bot', 'local_edesk', 'cloud_run',
                                'scripts', 'LEIA-ME.txt', 'Iniciar integração E-Desk.cmd',
                                'Parar integração E-Desk.cmd'}, name
        assert not any(part in {'.edesk-local', 'perfil', 'logs', '__pycache__'} for part in path.parts), name
    for source in ['edesk_bot/edesk_horas.py', 'edesk_bot/edesk_comentario.py', 'edesk_bot/comment_percentage.py', 'edesk_bot/config.py', 'scripts/start_full_integration.ps1', 'cloud_run/main.py']:
        assert archive.read(source) == (ROOT / source).read_bytes()
    with tempfile.TemporaryDirectory(prefix='complete package ', dir=VALIDATION) as temporary:
        extracted = Path(temporary).resolve()
        assert extracted.is_relative_to(VALIDATION.resolve())
        archive.extractall(extracted)
        runtime = extracted / 'python/python.exe'
        env = dict(os.environ, PYTHONNOUSERSITE='1',
                   PLAYWRIGHT_BROWSERS_PATH=str(extracted / 'python/ms-playwright'),
                   EDESK_LOCAL_MODE='true', EDESK_INTEGRATION_VERSION='comment-request-tab-6',
                   EDESK_DATA_DIR=str(extracted / 'test-state'))
        env.pop('PYTHONPATH', None)
        env.pop('PYTHONHOME', None)
        code = '''
import sys
from pathlib import Path
sys.path.insert(0,str(Path.cwd()/'edesk_bot'))
import flask,google.auth,cachecontrol,waitress,win32com.client,tkinter
from PIL import Image
import edesk_horas,edesk_comentario,edesk_fases
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,executable_path=p.chromium.executable_path)
    page=browser.new_page()
    page.set_content('<h1>Runtime portable OK</h1>')
    assert page.locator('h1').inner_text()=='Runtime portable OK'
    page.set_content('<ul class="RadTabStrip"><li><a class="rtsLink" onclick="this.classList.add(&quot;rtsSelected&quot;)"><span>Coment&#225;rios (27)</span></a></li></ul><button id="cph1_BtCom">Coment&#225;rio</button>')
    edesk_comentario.selecionar_aba_comentarios(page)
    assert page.locator('.rtsSelected').count()==1
    browser.close()
print('EXTRACTED_RUNTIME_AND_BROWSER_OK')
'''
        result = subprocess.run([str(runtime), '-c', code], cwd=extracted,
                                env=env, capture_output=True, text=True, timeout=120)
        assert result.returncode == 0, result.stderr
        print(result.stdout.strip(), flush=True)
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            port = listener.getsockname()[1]
        server_code = f'from local_edesk.server import app;from waitress import serve;serve(app,host="127.0.0.1",port={port})'
        server = subprocess.Popen([str(runtime), '-c', server_code], cwd=extracted,
                                  env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            base = f'http://127.0.0.1:{port}'
            for attempt in range(60):
                try:
                    response = requests.get(base + '/healthz', timeout=1)
                    if response.status_code == 200:
                        break
                except requests.RequestException:
                    pass
                assert server.poll() is None, 'Extracted service stopped unexpectedly'
                time.sleep(.25)
            health = response.json()
            assert health['mode'] == 'local' and health['status'] == 'ok'
            assert health['integrationPackageVersion'] == 'comment-request-tab-6'
            assert health['commentPercentage'] is True
            assert health['excelMirror'] and 'preview' in health['nativeActions']
            for route in ['/api/edesk/horas', '/api/edesk/fases',
                          '/api/edesk/comentarios', '/api/local-files']:
                response = requests.post(base + route, json={},
                    headers={'Origin': 'https://gerenciador-horas.web.app'}, timeout=5)
                assert response.status_code == 401, (route, response.status_code)
            print('EXTRACTED_FULL_SERVICE_OK: health, Excel capability, protected APIs', flush=True)
        finally:
            server.terminate()
            server.wait(timeout=10)
print('COMPLETE_PACKAGE_VALIDATED: no credentials, profiles, user data, or live sends')
