"""Smoke-test extracted runtime and APIs; never send data to E-Desk."""
import hashlib
import json
import os
import re
import socket
import subprocess
import tempfile
import time
import zipfile
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'web/downloads/integracao-edesk-completa-windows-v2.zip'
PACKAGE_VERSION = re.search(r"EDESK_INTEGRATION_VERSION = '([^']+)'", (ROOT / 'scripts/start_full_integration.ps1').read_text(encoding='utf-8'))[1]
VALIDATION = ROOT / 'build/full-integration-validation'
VALIDATION.mkdir(parents=True, exist_ok=True)

with zipfile.ZipFile(PACKAGE) as archive:
    for name in archive.namelist():
        path = Path(name)
        assert not path.is_absolute() and '..' not in path.parts
        assert path.parts[0] in {'python', 'edesk_bot', 'local_edesk', 'cloud_run',
                                'scripts', 'LEIA-ME.txt', 'Iniciar integração E-Desk.cmd',
                                'Parar integração E-Desk.cmd', 'Ativar inicio automatico.cmd',
                                'Desativar inicio automatico.cmd'}, name
        assert not any(part in {'.edesk-local', 'perfil', 'logs', '__pycache__'} for part in path.parts), name
    for name, disable in [('Ativar inicio automatico.cmd', False), ('Desativar inicio automatico.cmd', True)]:
        command = archive.read(name).decode('utf-8')
        assert 'scripts\\integration_autostart.ps1' in command
        assert ('-Disable' in command) == disable
    for source in ['scripts/integration_autostart.ps1', 'scripts/start_integration_background.ps1', 'local_edesk/local_files.py', 'local_edesk/excel_editor.py', 'local_edesk/consultoria_rows.py', 'local_edesk/excel_mirror.py', 'edesk_bot/excel_preview.py', 'local_edesk/project_archive.py', 'local_edesk/backup_policy.py', 'local_edesk/files_server.py', 'scripts/migrate_integration_data.py', 'scripts/start_local_files.ps1', 'edesk_bot/edesk_horas.py', 'edesk_bot/hour_receipt.py', 'edesk_bot/edesk_conferencia.py', 'edesk_bot/phase_audit.py', 'edesk_bot/edesk_recebidos.py', 'local_edesk/journal.py', 'edesk_bot/work_selection.py', 'edesk_bot/edesk_comentario.py', 'edesk_bot/edesk_percentual.py', 'edesk_bot/comment_percentage.py', 'edesk_bot/config.py', 'scripts/start_full_integration.ps1', 'cloud_run/main.py']:
        assert archive.read(source) == (ROOT / source).read_bytes()
    with tempfile.TemporaryDirectory(prefix='complete package ', dir=VALIDATION) as temporary:
        extracted = Path(temporary).resolve()
        assert extracted.is_relative_to(VALIDATION.resolve())
        archive.extractall(extracted)
        runtime = extracted / 'python/python.exe'
        env = dict(os.environ, PYTHONNOUSERSITE='1',
                   PLAYWRIGHT_BROWSERS_PATH=str(extracted / 'python/ms-playwright'),
                   EDESK_LOCAL_MODE='true', EDESK_INTEGRATION_VERSION=PACKAGE_VERSION,
                   EDESK_DATA_DIR=str(extracted / 'test-state'))
        env.pop('PYTHONPATH', None)
        env.pop('PYTHONHOME', None)
        code = '''
import sys
from pathlib import Path
sys.path.insert(0,str(Path.cwd()/'edesk_bot'))
import flask,google.auth,cachecontrol,waitress,win32com.client,tkinter
from PIL import Image
import edesk_horas,edesk_comentario,edesk_percentual,edesk_fases
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,executable_path=p.chromium.executable_path)
    page=browser.new_page()
    page.set_content('<h1>Runtime portable OK</h1>')
    assert page.locator('h1').inner_text()=='Runtime portable OK'
    page.set_content('<ul class="RadTabStrip"><li><a class="rtsLink" onclick="this.classList.add(&quot;rtsSelected&quot;)"><span>Coment&#225;rios (27)</span></a></li></ul><button id="cph1_BtCom">Coment&#225;rio</button>')
    edesk_comentario.selecionar_aba_comentarios(page)
    assert page.locator('.rtsSelected').count()==1
    for action in ['<input id="requestComment" type="button" value="Coment&#225;rio">',
                   '<button id="differentId">Coment&#225;rio</button>',
                   '<a href="#" id="commentLink">Coment&#225;rio</a>']:
        page.set_content('<a role="tab">Coment&#225;rios (27)</a>' + action)
        action_button = edesk_comentario.localizar_botao_comentario(page)
        action_button.evaluate("e => e.onclick = () => { const s=document.createElement('select'); s.id='popC_ddlTipCom'; document.body.appendChild(s); }")
        comment_page, frame = edesk_comentario.abrir_comentario(page, page.context)
        assert comment_page is page and frame is page
    print('REQUEST_COMMENT_BUTTON_VARIANTS_OK')
    browser.close()
print('EXTRACTED_RUNTIME_AND_BROWSER_OK')
'''
        result = subprocess.run([str(runtime), '-c', code], cwd=extracted,
                                env=env, capture_output=True, text=True, timeout=120)
        assert result.returncode == 0, result.stderr
        print(result.stdout.strip(), flush=True)
        percentage_check = subprocess.run([str(runtime), str(ROOT / 'scripts/check_comment_percentage_flow.py'), str(extracted / 'edesk_bot')],
            cwd=extracted, env=env, capture_output=True, text=True, timeout=120)
        assert percentage_check.returncode == 0, percentage_check.stderr
        print(percentage_check.stdout.strip(), flush=True)
        close_check = subprocess.run([str(runtime), str(ROOT / 'scripts/check_comment_close_flow.py'), str(extracted / 'edesk_bot')],
            cwd=extracted, env=env, capture_output=True, text=True, timeout=120)
        assert close_check.returncode == 0, close_check.stderr
        print(close_check.stdout.strip(), flush=True)
        cold_check = subprocess.run([str(runtime), str(ROOT / 'scripts/check_hours_cold_start.py'), str(extracted / 'edesk_bot')],
            cwd=extracted, env=env, capture_output=True, text=True, timeout=120)
        assert cold_check.returncode == 0, cold_check.stderr
        print(cold_check.stdout.strip(), flush=True)
        identity_check = subprocess.run([str(runtime), str(ROOT / 'scripts/check_work_identity_flow.py'), str(extracted / 'edesk_bot')],
            cwd=extracted, env=env, capture_output=True, text=True, timeout=120)
        assert identity_check.returncode == 0, identity_check.stderr
        print(identity_check.stdout.strip(), flush=True)
        audit_check = subprocess.run([str(runtime), str(ROOT / 'scripts/check_work_audit_flow.py'), str(extracted / 'edesk_bot')],
            cwd=extracted, env=env, capture_output=True, text=True, timeout=150)
        assert audit_check.returncode == 0, audit_check.stderr
        print(audit_check.stdout.strip(), flush=True)
        inbox_check = subprocess.run([str(runtime), str(ROOT / 'scripts/check_received_grid_flow.py'), str(extracted / 'edesk_bot')],
            cwd=extracted, env=env, capture_output=True, text=True, timeout=120)
        assert inbox_check.returncode == 0, inbox_check.stderr
        print(inbox_check.stdout.strip(), flush=True)
        receipt_check = subprocess.run([str(runtime), str(ROOT / 'scripts/check_hours_receipt_flow.py'), str(extracted / 'edesk_bot')],
            cwd=extracted, env=env, capture_output=True, text=True, timeout=240)
        assert receipt_check.returncode == 0, receipt_check.stderr
        print(receipt_check.stdout.strip(), flush=True)
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
            assert health['hoursReconciliation'] is True
            assert health['hoursTimesheet'] is True
            assert health['workAudit'] is True
            assert health['workEnumeration'] is True
            assert health['workInbox'] is True
            assert health['integrationPackageVersion'] == PACKAGE_VERSION
            assert health['nativeProjectLinkRecovery'] is True
            assert health['verifiedProjectMove'] is True
            assert health['nativeSpreadsheetSheetNames'] is True
            assert 'excel-editor-sheets' in health['nativeActions']
            assert 'authorize' in health['nativeActions']
            assert 'excel-editor-preview' in health['nativeActions']
            assert health['projectRootMove'] is True
            assert health['nativeSpreadsheetLayouts'] == ['enterprise', 'professional-maker']
            assert health['commentPercentageReceipt'] is True
            assert health['nativeFilesVersion'] == 'persistent-file-links-7'
            assert health['durableLocalLinks'] is True
            assert health['commentPercentage'] is True
            assert health['standalonePercentage'] is True
            assert health['excelMirror'] and 'preview' in health['nativeActions']
            for route in ['/api/edesk/horas', '/api/edesk/fases',
                          '/api/edesk/comentarios', '/api/edesk/percentual', '/api/local-files']:
                response = requests.post(base + route, json={},
                    headers={'Origin': 'https://gerenciador-horas.web.app'}, timeout=5)
                assert response.status_code == 401, (route, response.status_code)
            print('EXTRACTED_FULL_SERVICE_OK: health, Excel capability, protected APIs', flush=True)
        finally:
            server.terminate()
            server.wait(timeout=10)
print('COMPLETE_PACKAGE_VALIDATED: no credentials, profiles, user data, or live sends')
