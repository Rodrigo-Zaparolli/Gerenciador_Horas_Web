import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

class CommentGridStartupTest(unittest.TestCase):
    def test_comment_navigation_references_the_existing_grid_function(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as temporary:
            env = dict(os.environ, EDESK_DATA_DIR=temporary)
            program = "import sys;sys.path.insert(0,sys.argv[1]);import edesk_comentario as c;import edesk_horas as h;assert callable(c.acessar_minha_grid)"
            result = subprocess.run([sys.executable, '-I', '-c', program, str(root / 'edesk_bot')],
                env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_grid_waits_for_search_field_without_requiring_initial_results(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as temporary:
            env = dict(os.environ, EDESK_DATA_DIR=temporary)
            program = """
import sys
sys.path.insert(0,sys.argv[1])
import edesk_comentario as c
from types import SimpleNamespace
calls=[]
field=SimpleNamespace(wait_for=lambda **kwargs: calls.append(('ready',kwargs)))
page=SimpleNamespace(url='https://example.test/?GUID=fixture',
 goto=lambda *args,**kwargs: calls.append(('goto',args)),
 locator=lambda selector: (calls.append(('selector',selector)) or SimpleNamespace(first=field)))
c.acessar_minha_grid(page,'fixture')
assert ('selector','#cph1_txtSol') in calls
assert calls[-1][0]=='ready'
"""
            result = subprocess.run([sys.executable,'-I','-c',program,str(root/'edesk_bot')],
                env=env,capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr)

    def test_comment_opens_request_without_work_or_retroactive(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as temporary:
            program = """
import sys
sys.path.insert(0,sys.argv[1])
import edesk_comentario as c
import edesk_horas as h
from unittest.mock import Mock, patch
request=Mock()
request.url='https://example.test/Solicitacao.aspx?GUID=fixture'
request.is_closed.return_value=False
request.locator.return_value.first.wait_for.return_value=None
context=Mock(pages=[request])
with patch.object(h,'abrir_trabalho_na_solicitacao',side_effect=AssertionError('work must not open')), patch.object(h,'fechar_solicitacoes_duplicadas'):
 result=c.abrir_solicitacao_para_comentario(request,context,None,'2261914',request)
 assert result is request
 request.locator.assert_called_with('#cph1_BtCom')
 request.bring_to_front.assert_called_once()
"""
            result=subprocess.run([sys.executable,'-I','-c',program,str(root/'edesk_bot')],
                env=dict(os.environ,EDESK_DATA_DIR=temporary),capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr)

    def test_navigation_errors_are_specific_and_do_not_expose_raw_logs(self):
        from cloud_run import main
        for marker in ['EDESK_GRID_SEARCH_NOT_READY', 'EDESK_COMMENT_REQUEST_NOT_FOUND', 'EDESK_COMMENT_WORK_NOT_OPENED']:
            message = main._automation_failure_message(marker + ' secret-token private-session-url')
            self.assertIn('Nenhum coment\u00e1rio foi enviado', message)
            self.assertNotIn('secret-token', message)
            self.assertNotIn('private-session-url', message)
