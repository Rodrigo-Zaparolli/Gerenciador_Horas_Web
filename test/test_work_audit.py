import ast
import json
import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'edesk_bot'))
os.environ['EDESK_LOCAL_MODE'] = 'true'
from edesk_conferencia import mutation_request
from cloud_run.main import app, _validate_automation_request


class WorkAuditTests(unittest.TestCase):
    def setUp(self):
        self.data = {'edeskCredenciais': {'email': 'test@example.com', 'senha': 'test'},
                     'solicitacoes': [{'solicitacao': '226144', 'trabalhos': ['3']}]}
        self.headers = {'Origin': 'https://gerenciador-horas.web.app', 'Authorization': 'Bearer test'}

    def test_query_rejects_send_invalid_targets_and_unbounded_lists(self):
        self.assertIsNone(_validate_automation_request('conferencia', self.data, False))
        self.assertIsNotNone(_validate_automation_request('conferencia', self.data, True))
        for targets in [[], [{}], [{'solicitacao':'226144','trabalhos':['abc']}], self.data['solicitacoes']*101]:
            self.assertIsNotNone(_validate_automation_request('conferencia', {**self.data,'solicitacoes':targets}, False))

    def test_guard_blocks_save_delete_and_aspnet_commands_but_allows_navigation_and_login(self):
        for data in ['cph1%24BtAtu=Salvar','__EVENTTARGET=cph1%24BtAtu','__EVENTTARGET=cph1%24BtExcluir','save=1']:
            self.assertTrue(mutation_request(SimpleNamespace(method='POST',post_data=data)), data)
        for data in ['__EVENTTARGET=cph1%24gvwTra%24ctl03%24btnSelTra','email=test&password=secret','__EVENTTARGET=cph1%24BtPes']:
            self.assertFalse(mutation_request(SimpleNamespace(method='POST',post_data=data)), data)

    def test_worker_has_no_calls_that_fill_work_fields_or_save(self):
        tree=ast.parse((ROOT/'edesk_bot/edesk_conferencia.py').read_text(encoding='utf-8'))
        calls=[node.func.attr if isinstance(node.func,ast.Attribute) else node.func.id if isinstance(node.func,ast.Name) else ''
               for node in ast.walk(tree) if isinstance(node,ast.Call)]
        for forbidden in ['fill','save_work_percentage','salvar_hora','salvar_comentario','salvar_fases']:
            self.assertNotIn(forbidden,calls)

    def test_endpoint_enforces_verified_pilot_identity_and_preserves_read_only_payload(self):
        with app.test_client() as client, patch('local_edesk.authentication.verify_token',side_effect=ValueError('invalid token')), patch('cloud_run.main.subprocess.Popen') as process:
            response=client.post('/api/edesk/conferencia',headers=self.headers,json={'request':self.data,'enviar':False})
            self.assertEqual(response.status_code,401);process.assert_not_called()
        receipt={'ok':True,'operation':'conferencia','rows':[{'solicitacao':'226144','idTrabalho':'3','values':{'percentage':'70'}}],'message':'Consulta concluida'}
        def launch(command,**kwargs):
            data=json.loads(Path(command[-1]).read_text(encoding='utf-8'))
            self.assertIs(data['enviar'],False)
            return SimpleNamespace(returncode=0,communicate=lambda **_: (json.dumps(receipt),''))
        with app.test_client() as client, patch('local_edesk.authentication.verify_token',return_value={'sub':'test','email':'other@example.com'}), patch('cloud_run.main.subprocess.Popen',side_effect=launch):
            response=client.post('/api/edesk/conferencia',headers=self.headers,json={'request':self.data,'enviar':False})
            self.assertEqual(response.status_code,200)
            self.assertEqual(json.loads(response.json['responseBody']),receipt)
            self.assertTrue(response.json['confirmed'])


if __name__ == '__main__':
    unittest.main()
