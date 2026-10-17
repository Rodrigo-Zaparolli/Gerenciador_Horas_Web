import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

os.environ['EDESK_LOCAL_MODE'] = 'true'
from cloud_run.main import app

HEADERS = {'Origin': 'https://gerenciador-horas.web.app', 'Authorization': 'Bearer fake-token'}

class StandalonePercentageTest(unittest.TestCase):
    def test_invalid_or_comment_content_never_starts_an_operation(self):
        base = {'edeskCredenciais': {'email': 'test', 'senha': 'test'},
                'solicitacao': '226144', 'idTrabalho': '6', 'percentualRealizado': 25}
        with patch('local_edesk.authentication.verify_token', return_value={'sub': 'test'}), patch('cloud_run.main.subprocess.Popen') as process:
            with app.test_client() as client:
                for change, send in [({'percentualRealizado': None}, True), ({'percentualRealizado': 101}, True),
                                     ({'solicitacao': ''}, True), ({'texto': 'Do not publish'}, True),
                                     ({'imagemBase64': 'fake-image'}, True), ({}, False)]:
                    response = client.post('/api/edesk/percentual', headers=HEADERS,
                        json={'request': {**base, **change}, 'enviar': send})
                    self.assertEqual(response.status_code, 400, response.json)
            process.assert_not_called()

    def test_server_requires_the_percentage_result_and_uses_dedicated_script(self):
        data = {'edeskCredenciais': {'email': 'test', 'senha': 'test'},
                'solicitacao': '226144', 'idTrabalho': '6', 'percentualRealizado': 0}
        for result, expected in [({}, 502), ({'ok': True}, 502),
                                 ({'ok': True, 'operation': 'percentual', 'message': 'Confirmed'}, 200)]:
            with patch('local_edesk.authentication.verify_token', return_value={'sub': 'test'}), \
                 patch('cloud_run.main._local_browser_profile', return_value='isolated-fixture'), \
                 patch('cloud_run.main.subprocess.Popen') as process:
                def create(command, **kwargs):
                    self.assertEqual(Path(command[1]).name, 'edesk_percentual.py')
                    payload = json.loads(Path(command[2]).read_text(encoding='utf-8'))
                    self.assertNotIn('texto', payload)
                    self.assertNotIn('imagemBase64', payload)
                    process.return_value.returncode = 0
                    process.return_value.communicate.return_value = (json.dumps(result), '')
                    return process.return_value
                process.side_effect = create
                response = app.test_client().post('/api/edesk/percentual', headers=HEADERS,
                    json={'request': data, 'enviar': True})
                self.assertEqual(response.status_code, expected, response.json)
                self.assertEqual(response.json['confirmed'], expected == 200)

    def test_percentage_mode_never_opens_fills_or_saves_a_comment(self):
        root = Path(__file__).resolve().parents[1]
        program = '''
import sys
from unittest.mock import Mock, patch
from contextlib import ExitStack
sys.path.insert(0, sys.argv[1])
import edesk_comentario as bot
page=Mock(url='https://fixture.invalid/Portal/PortalAtendente.aspx?GUID=fixture')
request_page=Mock(url='https://fixture.invalid/Portal/Solicitacao.aspx?GUID=fixture&solicitacao=226144')
context=Mock(pages=[page])
playwright=Mock()
playwright.chromium.launch_persistent_context.return_value=context
manager=Mock()
manager.__enter__=Mock(return_value=playwright)
manager.__exit__=Mock(return_value=False)
with ExitStack() as stack:
    stack.enter_context(patch.object(bot,'sync_playwright',return_value=manager))
    stack.enter_context(patch.object(bot,'carregar_request',return_value={'url':'https://promob.e-desk.com.br','solicitacao':'226144','idTrabalho':'6','percentualRealizado':'91.5','enviar':True}))
    for name in ['log','restore_session_cookies','save_session_cookies','instalar_monitor_requests','acessar_minha_grid']:
        stack.enter_context(patch.object(bot,name))
    stack.enter_context(patch.object(bot,'localizar_solicitacao_validada',return_value=(page,None,request_page)))
    stack.enter_context(patch.object(bot,'abrir_solicitacao_para_comentario',return_value=request_page))
    comments=[stack.enter_context(patch.object(bot,name,side_effect=AssertionError('Must never touch comments'))) for name in ['abrir_comentario','preencher_comentario','salvar_comentario']]
    percentage=stack.enter_context(patch.object(bot,'update_percentage_after_comment'))
    assert bot.main(percentage_only=True)==0
    percentage.assert_called_once()
    assert percentage.call_args.args[2:5]==(request_page.url,'226144','6')
    for comment in comments: comment.assert_not_called()
print('PERCENTAGE_ONLY_NO_COMMENT_ACTIONS_OK')
'''
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run([sys.executable, '-I', '-c', program, str(root / 'edesk_bot')],
                env={**os.environ, 'EDESK_DATA_DIR': temporary}, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('PERCENTAGE_ONLY_NO_COMMENT_ACTIONS_OK', result.stdout)

if __name__ == '__main__':
    unittest.main()
