import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ['EDESK_LOCAL_MODE'] = 'true'
from cloud_run.main import app, automation_lock
from local_edesk import central

ORIGIN = 'https://gerenciador-horas.web.app'


class CentralTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.environment = patch.dict(os.environ, {
            'EDESK_CENTRAL_MODE': 'true', 'EDESK_CENTRAL_HOST': '192.168.1.10',
            'EDESK_CENTRAL_ACCESS_PATH': str(Path(self.directory.name) / 'access.json'),
        })
        self.environment.start()
        self.client = app.test_client()
        self.user = {'sub': 'owner'}
        self.verifier = patch('local_edesk.authentication.verify_token', side_effect=lambda _: self.user)
        self.verifier.start()
        self.headers = {'Origin': ORIGIN, 'Authorization': 'Bearer fake-token'}

    def tearDown(self):
        self.verifier.stop()
        self.environment.stop()
        self.directory.cleanup()

    def get(self, path, remote='192.168.1.20', host='192.168.1.10:8765'):
        return self.client.get(path, headers={**self.headers, 'Host': host},
                               environ_overrides={'REMOTE_ADDR': remote})

    def pair(self, remote='127.0.0.1', host='127.0.0.1:8765'):
        return self.client.post('/api/edesk/central/pair', json={},
            headers={**self.headers, 'Host': host}, environ_overrides={'REMOTE_ADDR': remote})

    def test_closed_until_authorized_and_initial_pairing_is_loopback_only(self):
        self.assertEqual(self.get('/api/edesk/session').status_code, 403)
        self.assertEqual(self.pair(remote='192.168.1.20').status_code, 403)
        self.assertEqual(self.pair(host='192.168.1.10:8765').status_code, 403)
        response = self.pair()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['url'], 'http://192.168.1.10:8765')
        self.assertTrue(self.get('/api/edesk/session').json['authorized'])
        self.user = {'sub': 'different'}
        self.assertEqual(self.pair().status_code, 403)
        self.assertEqual(self.get('/api/edesk/session').status_code, 403)

    def test_host_origin_public_network_and_token_are_checked(self):
        self.assertEqual(self.get('/healthz', remote='8.8.8.8').status_code, 403)
        self.assertEqual(self.get('/healthz', host='attacker.example:8765').status_code, 403)
        response = self.client.options('/api/edesk/horas', headers={'Host': '192.168.1.10:8765', 'Origin': ORIGIN},
            environ_overrides={'REMOTE_ADDR': '192.168.1.20'})
        self.assertEqual(response.status_code, 204)
        self.assertEqual(response.headers['Access-Control-Allow-Private-Network'], 'true')
        self.assertEqual(self.client.get('/api/edesk/session').status_code, 401)
        self.assertEqual(self.client.get('/healthz', headers={'Origin': 'https://attacker.example'}).status_code, 403)

    def test_only_owner_can_authorize_and_owner_cannot_remove_itself(self):
        self.pair()
        response = self.client.post('/api/edesk/central/access', json={'users': ['second']}, headers=self.headers)
        self.assertEqual(response.json['users'], ['owner', 'second'])
        self.user = {'sub': 'second'}
        self.assertTrue(self.get('/api/edesk/session').json['authorized'])
        self.assertEqual(self.client.post('/api/edesk/central/access', json={'users': ['third']}, headers=self.headers).status_code, 403)
        self.user = {'sub': 'owner'}
        self.assertEqual(self.client.post('/api/edesk/central/access', json={}, headers=self.headers).status_code, 400)
        self.assertEqual(self.client.post('/api/edesk/central/access', json={'users': [12]}, headers=self.headers).status_code, 400)

    def test_authorization_persists_and_unknown_account_never_runs_script(self):
        self.pair()
        self.assertTrue(central.permitted('owner'))
        self.assertEqual(central.pair('owner')['users'], ['owner'])
        self.user = {'sub': 'unknown'}
        with patch('cloud_run.main.subprocess.Popen') as process:
            response = self.client.post('/api/edesk/horas', headers=self.headers, json={})
            self.assertEqual(response.status_code, 403)
            process.assert_not_called()

    def test_history_is_scoped_to_authorized_account_and_busy_blocks_sends(self):
        self.pair()
        with patch('local_edesk.journal.states', return_value={}) as states:
            self.assertEqual(self.get('/api/edesk/history').status_code, 200)
            states.assert_called_once_with('owner')
        automation_lock.acquire()
        try:
            response = self.client.post('/api/edesk/horas', headers=self.headers,
                json={'request': {'edeskCredenciais': {'email': 'test', 'senha': 'test'},
                      'trabalhos': [{}]}, 'enviar': False})
            self.assertEqual(response.status_code, 409)
        finally:
            automation_lock.release()

    def test_only_rfc1918_addresses_are_private(self):
        for value in ('10.0.0.1', '172.16.0.1', '172.31.255.255', '192.168.1.10'):
            self.assertTrue(central.private_address(value))
        for value in ('127.0.0.1', '169.254.1.1', '172.32.0.1', '8.8.8.8', '192.168.999.1', '::1'):
            self.assertFalse(central.private_address(value))


if __name__ == '__main__':
    unittest.main()
