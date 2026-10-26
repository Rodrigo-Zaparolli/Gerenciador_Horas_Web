import ast
import json
import os
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ['EDESK_LOCAL_MODE']='true'
from cloud_run.main import app,_validate_automation_request


class ReceivedWorkTests(unittest.TestCase):
    def setUp(self):
        self.data={'edeskCredenciais':{'email':'test@example.com','senha':'test'}}
        self.headers={'Origin':'https://gerenciador-horas.web.app','Authorization':'Bearer test'}

    def test_inbox_requires_read_only_execution_and_credentials(self):
        self.assertIsNone(_validate_automation_request('recebidos',self.data,False))
        self.assertIsNotNone(_validate_automation_request('recebidos',self.data,True))
        self.assertIsNotNone(_validate_automation_request('recebidos',{},False))

    def test_endpoint_checks_verified_identity_and_returns_the_grid_without_creating_work(self):
        with app.test_client() as client,patch('local_edesk.authentication.verify_token',side_effect=ValueError('invalid token')),patch('cloud_run.main.subprocess.Popen') as process:
            response=client.post('/api/edesk/recebidos',headers=self.headers,json={'request':self.data,'enviar':False})
            self.assertEqual(response.status_code,401);process.assert_not_called()
        receipt={'ok':True,'operation':'recebidos','complete':True,'rows':[{'solicitacao':'226144','idTrabalho':'3'}]}
        def launch(command,**kwargs):
            self.assertTrue(command[-2].endswith('edesk_recebidos.py'))
            self.assertIs(json.loads(Path(command[-1]).read_text(encoding='utf-8'))['enviar'],False)
            return SimpleNamespace(returncode=0,communicate=lambda **_: (json.dumps(receipt),''))
        with app.test_client() as client,patch('local_edesk.authentication.verify_token',return_value={'sub':'owner','email':'other@example.com'}),patch('cloud_run.main.subprocess.Popen',side_effect=launch):
            response=client.post('/api/edesk/recebidos',headers=self.headers,json={'request':self.data,'enviar':False})
            self.assertEqual(response.status_code,200)
            self.assertEqual(json.loads(response.json['responseBody']),receipt)

    def test_worker_never_saves_and_only_fills_the_search_filter(self):
        path=Path(__file__).resolve().parents[1]/'edesk_bot/edesk_recebidos.py'
        tree=ast.parse(path.read_text(encoding='utf-8'))
        calls=[node.func for node in ast.walk(tree) if isinstance(node,ast.Call)]
        for call in calls:
            name=call.attr if isinstance(call,ast.Attribute) else call.id if isinstance(call,ast.Name) else ''
            self.assertNotIn(name,{'salvar_hora','salvar_comentario','save_work_percentage','salvar_fases'})
            if name=='fill':self.assertEqual(ast.unparse(call.value),'search')


if __name__=='__main__':unittest.main()
